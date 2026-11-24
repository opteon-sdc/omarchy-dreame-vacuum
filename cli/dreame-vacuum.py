#!/usr/bin/env python3
"""dreame-vacuum: control a Dreame robot vacuum from the command line.

A small daemon (`dreame-vacuum serve`) logs in to the Dreamehome cloud once,
keeps the connection open with Tasshack's `dreame` library
(https://github.com/Tasshack/dreame-vacuum) and listens on a Unix socket.
Every other command is a thin client of that socket, so it answers at once.

Output is a JSON document {"ok": true, "data": ...} or
{"ok": false, "error": {"message": ...}} with --output json, and short
human-readable text otherwise. `watch` prints one JSON state per line.
"""

from __future__ import annotations

import argparse
import getpass
import json
import logging
import os
import signal
import socket
import socketserver
import sys
import tempfile
import threading
import time
import traceback
from pathlib import Path

APP = "dreame-vacuum"
VERSION = "1.0.0"
ACCOUNT_TYPES = ("dreame", "mova", "trouver", "mi")
COUNTRIES = ("eu", "cn", "us", "ru", "sg", "kr", "by")
SUCTION_LEVELS = ("quiet", "standard", "strong", "turbo")
MAX_LINE = 64 * 1024

LOG = logging.getLogger(APP)


# ---------------------------------------------------------------- paths


def config_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / APP


def config_path() -> Path:
    return config_dir() / "config.json"


def runtime_dir() -> Path:
    base = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
    return Path(base) / APP


def socket_path() -> Path:
    return runtime_dir() / "sock"


def map_path() -> Path:
    return runtime_dir() / "map.png"


def data_dir() -> Path:
    """Where setup put the vendored library and its translations."""
    here = Path(__file__).resolve().parent
    if (here / "lib" / "dreame").is_dir():
        return here
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share") / APP


# ---------------------------------------------------------------- config


def load_config() -> dict:
    try:
        with config_path().open(encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_config(cfg: dict) -> None:
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".config.", suffix=".json")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# ---------------------------------------------------------------- library


def import_library():
    lib = data_dir() / "lib"
    if str(lib) not in sys.path:
        sys.path.insert(0, str(lib))
    try:
        import dreame  # noqa: F401
    except ImportError as ex:
        raise SystemExit(
            f"The dreame library is not installed ({ex}). Run the plugin's setup script first."
        ) from None
    return dreame


class Locale:
    """Labels from the Home Assistant integration's translation files."""

    def __init__(self, lang: str):
        self.data = {}
        base = data_dir() / "lib" / "translations"
        for code in (lang, lang.split("-")[0], "en"):
            path = base / f"{code}.json"
            if path.is_file():
                try:
                    with path.open(encoding="utf-8") as f:
                        self.data = json.load(f)
                    break
                except (OSError, ValueError):
                    continue

    def state(self, platform: str, key: str, value) -> str:
        if value is None:
            return ""
        value = str(value)
        try:
            return self.data["entity"][platform][key]["state"][value]
        except (KeyError, TypeError):
            return value.replace("_", " ").capitalize()


_locales: dict[str, Locale] = {}


def locale_for(lang: str) -> Locale:
    lang = (lang or "en").strip() or "en"
    if lang not in _locales:
        _locales[lang] = Locale(lang)
    return _locales[lang]


# ---------------------------------------------------------------- daemon


def safe(fn, default=None):
    try:
        value = fn()
        return default if value is None else value
    except Exception:
        return default


def enum_name(value) -> str:
    name = getattr(value, "name", None)
    return name.lower() if isinstance(name, str) else ""


class Vacuum:
    """Owns the DreameVacuumDevice and turns it into plain state."""

    def __init__(self, cfg: dict):
        self.cfg = cfg
        self.lib = None
        self.device = None
        self.renderer = None
        self.lock = threading.RLock()
        self.changed = threading.Condition()
        self.serial = 0
        self.connecting = False
        self.last_error = ""
        self.auth_failed = False
        self.map_serial = 0
        self._map_key = None
        self._map_wanted = threading.Event()
        self._stopping = False

    # -- lifecycle

    @property
    def configured(self) -> bool:
        return bool(self.cfg.get("username") and self.cfg.get("password") and self.cfg.get("did"))

    def start(self):
        threading.Thread(target=self._connect_loop, name="connect", daemon=True).start()
        threading.Thread(target=self._map_loop, name="map", daemon=True).start()

    def stop(self):
        self._stopping = True
        self._map_wanted.set()
        with self.lock:
            if self.device is not None:
                try:
                    self.device.listen(None)
                    self.device.disconnect()
                except Exception:
                    pass

    def _connect_loop(self):
        if not self.configured:
            self.last_error = "not_configured"
            self.notify()
            return
        self.lib = import_library()
        from dreame import DreameVacuumDevice

        delay = 10
        while not self._stopping:
            self.connecting = True
            self.notify()
            cfg = self.cfg
            device = None
            try:
                device = DreameVacuumDevice(
                    cfg.get("name") or cfg.get("model") or "Dreame",
                    cfg.get("host"),
                    cfg.get("token") or " ",
                    cfg.get("mac"),
                    cfg.get("username"),
                    cfg.get("password"),
                    cfg.get("country") or "eu",
                    True,
                    cfg.get("account_type") or "dreame",
                    cfg.get("did"),
                    cfg.get("auth_key"),
                )
                device.listen(self._on_change)
                device.listen_error(self._on_error)
                device.update()
                if device.auth_failed:
                    self.auth_failed = True
                    raise RuntimeError("auth_failed")
                device.schedule_update()
                with self.lock:
                    self.device = device
                self._remember_auth_key()
                self.last_error = ""
                self.auth_failed = False
                self.connecting = False
                self._map_wanted.set()
                self.notify()
                LOG.info("Connected to %s", cfg.get("name") or cfg.get("model"))
                return
            except Exception as ex:
                LOG.warning("Connecting failed: %s", ex)
                LOG.debug("%s", traceback.format_exc())
                self.last_error = "auth_failed" if self.auth_failed else (str(ex) or type(ex).__name__)
                self.connecting = False
                self.notify()
                if device is not None:
                    try:
                        device.listen(None)
                        device.disconnect()
                    except Exception:
                        pass
                if self.auth_failed:
                    return
                time.sleep(delay)
                delay = min(delay * 2, 300)

    def _remember_auth_key(self):
        try:
            key = self.device._protocol.cloud.auth_key
        except Exception:
            return
        if key and key != self.cfg.get("auth_key"):
            self.cfg["auth_key"] = key
            try:
                save_config(self.cfg)
            except OSError as ex:
                LOG.warning("Could not save the auth key: %s", ex)

    def _on_change(self, *_args):
        self._map_wanted.set()
        self.notify()

    def _on_error(self, ex):
        self.last_error = str(ex) or type(ex).__name__
        self.notify()

    def notify(self):
        with self.changed:
            self.serial += 1
            self.changed.notify_all()

    # -- map

    def _map_loop(self):
        while not self._stopping:
            self._map_wanted.wait(timeout=60)
            self._map_wanted.clear()
            if self._stopping:
                return
            try:
                self._render_map()
            except Exception as ex:
                LOG.debug("Map render failed: %s", ex)
            # Re-render at most every few seconds while the robot moves.
            time.sleep(3)

    def _render_map(self):
        device = self.device
        if device is None:
            return
        status = device.status
        map_data = safe(lambda: status.current_map) or safe(lambda: status.selected_map)
        if map_data is None or safe(lambda: map_data.empty_map, False):
            return
        key = (
            safe(lambda: map_data.map_id),
            safe(lambda: map_data.frame_id),
            safe(lambda: map_data.last_updated),
            safe(lambda: status.robot_status, 0),
            safe(lambda: status.station_status, 0),
        )
        if key == self._map_key:
            return
        from dreame.map import DreameVacuumMapRenderer

        if self.renderer is None:
            self.renderer = DreameVacuumMapRenderer(
                self.cfg.get("map_color_scheme") or "Dreame Dark",
                None,
                [],
                safe(lambda: device.capability.robot_type, 0),
                False,
                False,
            )
        png = self.renderer.render_map(device.get_map_for_render(map_data), key[3], key[4])
        if not png:
            return
        path = map_path()
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(png)
        os.replace(tmp, path)
        self._map_key = key
        self.map_serial += 1
        self.notify()

    # -- state

    def state(self, lang: str = "en") -> dict:
        loc = locale_for(lang)
        out = {
            "configured": self.configured,
            "connected": False,
            "connecting": self.connecting,
            "error": self.last_error,
            "authFailed": self.auth_failed,
            "name": self.cfg.get("name") or "",
            "model": self.cfg.get("model") or "",
            "updated": int(time.time() * 1000),
        }
        device = self.device
        if device is None:
            return out
        s = device.status
        status = safe(lambda: s.status)
        status_key = safe(lambda: s.status_name, "unknown")
        task_key = safe(lambda: s.task_status_name, "unknown")
        error_key = safe(lambda: s.error_name, "")
        suction = enum_name(safe(lambda: s.suction_level))
        has_error = bool(safe(lambda: s.has_error, False))

        activity = "idle"
        if has_error:
            activity = "error"
        elif safe(lambda: s.returning, False):
            activity = "returning"
        elif safe(lambda: s.paused, False):
            activity = "paused"
        elif safe(lambda: s.running, False):
            activity = "cleaning"
        elif safe(lambda: s.washing, False):
            activity = "washing"
        elif safe(lambda: s.drying, False):
            activity = "drying"
        elif safe(lambda: s.charging, False):
            activity = "charging"
        elif safe(lambda: s.docked, False):
            activity = "docked"
        elif safe(lambda: s.sleeping, False):
            activity = "sleeping"

        P = self.lib.DreameVacuumProperty if self.lib else None

        def prop(name, default=None):
            if P is None:
                return default
            return safe(lambda: device.get_property(getattr(P, name)), default)

        room = safe(lambda: s.current_room)
        out.update(
            {
                "connected": bool(safe(lambda: device.device_connected, False)),
                "available": bool(safe(lambda: device.available, False)),
                "model": safe(lambda: device.info.model, out["model"]) or out["model"],
                "firmware": safe(lambda: device.info.firmware_version, ""),
                "activity": activity,
                "status": status_key,
                "statusLabel": loc.state("sensor", "status", status_key),
                "statusCode": int(status) if status is not None else -1,
                "taskStatus": task_key,
                "taskStatusLabel": loc.state("sensor", "task_status", task_key),
                "hasError": has_error,
                "hasWarning": bool(safe(lambda: s.has_warning, False)),
                "errorCode": error_key if has_error or safe(lambda: s.has_warning, False) else "",
                "errorLabel": loc.state("sensor", "error", error_key)
                if has_error or safe(lambda: s.has_warning, False)
                else "",
                "battery": int(safe(lambda: s.battery_level, 0) or 0),
                "charging": bool(safe(lambda: s.charging, False)),
                "docked": bool(safe(lambda: s.docked, False)),
                "running": bool(safe(lambda: s.running, False)),
                "paused": bool(safe(lambda: s.paused, False)),
                "returning": bool(safe(lambda: s.returning, False)),
                "suction": suction,
                "suctionLabel": loc.state("select", "suction_level", suction) if suction else "",
                "suctionOptions": [
                    {"value": v, "label": loc.state("select", "suction_level", v)} for v in SUCTION_LEVELS
                ],
                "suctionAvailable": not bool(safe(lambda: s.suction_unavailable, False)),
                "cleaningMode": safe(lambda: s.cleaning_mode_name, ""),
                "cleaningModeLabel": loc.state("select", "cleaning_mode", safe(lambda: s.cleaning_mode_name, ""))
                if safe(lambda: s.cleaning_mode_name, "")
                else "",
                "cleanedArea": prop("CLEANED_AREA", 0),
                "cleaningTime": prop("CLEANING_TIME", 0),
                "cleaningProgress": prop("CLEANING_PROGRESS"),
                "currentRoom": safe(lambda: room.name, "") if room is not None else "",
                "rooms": self._rooms(s),
                "consumables": self._consumables(s, loc),
                "map": {"path": str(map_path()), "serial": self.map_serial} if self.map_serial else None,
            }
        )
        return out

    @staticmethod
    def _rooms(s) -> list:
        rooms = []
        selected = safe(lambda: s.selected_map)
        segments = safe(lambda: selected.segments) if selected is not None else None
        if not segments:
            return rooms
        for seg_id, seg in sorted(segments.items(), key=lambda kv: (safe(lambda: kv[1].order) or 999, kv[0])):
            if safe(lambda: seg.visibility) is False:
                continue
            rooms.append(
                {
                    "id": int(seg_id),
                    "name": str(safe(lambda: seg.name, f"Room {seg_id}"))[:64],
                    "order": safe(lambda: seg.order),
                }
            )
        return rooms[:64]

    @staticmethod
    def _consumables(s, loc) -> list:
        out = []
        for key, attr in (
            ("main_brush_left", "main_brush_life"),
            ("side_brush_left", "side_brush_life"),
            ("filter_left", "filter_life"),
            ("mop_pad_left", "mop_life"),
            ("sensor_dirty_left", "sensor_dirty_life"),
        ):
            value = safe(lambda: getattr(s, attr))
            if isinstance(value, (int, float)) and value >= 0:
                try:
                    label = loc.data["entity"]["sensor"][key]["name"]
                except (KeyError, TypeError):
                    label = key.replace("_left", "").replace("_", " ").capitalize()
                out.append({"key": key.replace("_left", ""), "label": label, "percent": int(value)})
        return out

    # -- commands

    def run(self, cmd: str, args: dict):
        device = self.device
        if device is None:
            raise RuntimeError("not_connected" if self.configured else "not_configured")
        lib = self.lib
        with self.lock:
            if cmd == "start":
                device.start()
            elif cmd == "pause":
                device.pause()
            elif cmd == "stop":
                device.stop()
            elif cmd == "dock":
                device.return_to_base()
            elif cmd == "locate":
                device.locate()
            elif cmd == "toggle":
                s = device.status
                if s.running and not s.paused and not s.returning:
                    device.pause()
                else:
                    device.start()
            elif cmd == "suction":
                level = str(args.get("level", "")).lower()
                if level not in SUCTION_LEVELS:
                    raise ValueError(f"suction level must be one of: {', '.join(SUCTION_LEVELS)}")
                device.set_suction_level(getattr(lib.DreameVacuumSuctionLevel, level.upper()).value)
            elif cmd == "clean-rooms":
                rooms = args.get("rooms") or []
                if not isinstance(rooms, list) or not rooms or len(rooms) > 64:
                    raise ValueError("give one or more room ids")
                ids = [int(r) for r in rooms]
                repeats = max(1, min(3, int(args.get("repeats") or 1)))
                device.clean_segment(ids, repeats)
            else:
                raise ValueError(f"unknown command: {cmd}")
        device.schedule_update(1)
        self.notify()
        return {"command": cmd}


class Handler(socketserver.StreamRequestHandler):
    vacuum: Vacuum = None

    def handle(self):
        line = self.rfile.readline(MAX_LINE)
        try:
            req = json.loads(line or b"{}")
            if not isinstance(req, dict):
                raise ValueError
        except ValueError:
            return self.reply({"ok": False, "error": {"message": "bad request"}})
        cmd = str(req.get("cmd", ""))
        args = req.get("args") if isinstance(req.get("args"), dict) else {}
        lang = str(req.get("lang") or "en")[:16]
        v = self.vacuum
        if cmd == "watch":
            return self.watch(lang)
        if cmd == "status":
            return self.reply({"ok": True, "data": v.state(lang)})
        try:
            data = v.run(cmd, args)
            self.reply({"ok": True, "data": data})
        except Exception as ex:
            key = getattr(ex, "key", None)
            LOG.info("Command %s failed: %s", cmd, ex)
            self.reply({"ok": False, "error": {"message": str(key or ex) or type(ex).__name__}})

    def reply(self, doc):
        self.wfile.write((json.dumps(doc, ensure_ascii=False) + "\n").encode())
        self.wfile.flush()

    def watch(self, lang):
        v = self.vacuum
        last = None
        seen = -1
        while True:
            with v.changed:
                if v.serial == seen:
                    v.changed.wait(timeout=30)
                seen = v.serial
            state = v.state(lang)
            compare = dict(state, updated=0)
            if compare == last:
                continue
            last = compare
            try:
                self.reply({"ok": True, "data": state})
            except (BrokenPipeError, ConnectionResetError, OSError):
                return


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def serve(args):
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )
    if not args.verbose:
        # The library is chatty at INFO.
        logging.getLogger("dreame").setLevel(logging.WARNING)
        logging.getLogger("custom_components").setLevel(logging.WARNING)

    path = socket_path()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    if path.exists():
        if ping():
            raise SystemExit(f"{APP} is already running")
        path.unlink()

    vacuum = Vacuum(load_config())
    Handler.vacuum = vacuum
    server = Server(str(path), Handler)
    os.chmod(path, 0o600)

    def shutdown(*_):
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    vacuum.start()
    LOG.info("Listening on %s", path)
    try:
        server.serve_forever()
    finally:
        vacuum.stop()
        server.server_close()
        try:
            path.unlink()
        except OSError:
            pass


# ---------------------------------------------------------------- client


def ping() -> bool:
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            s.connect(str(socket_path()))
        return True
    except OSError:
        return False


def request(cmd: str, args: dict | None = None, lang: str = "en", timeout: float = 30):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(str(socket_path()))
    except OSError:
        s.close()
        raise ConnectionError("daemon_not_running") from None
    s.sendall((json.dumps({"cmd": cmd, "args": args or {}, "lang": lang}) + "\n").encode())
    return s


def call(cmd, args=None, lang="en"):
    with request(cmd, args, lang) as s:
        f = s.makefile("rb")
        line = f.readline(4 * MAX_LINE)
    if not line:
        raise ConnectionError("no answer from the daemon")
    return json.loads(line)


def emit(output: str, doc: dict, text: str = ""):
    if output == "json":
        print(json.dumps(doc, ensure_ascii=False))
    elif doc.get("ok"):
        if text:
            print(text)
    else:
        print(f"{APP}: {doc.get('error', {}).get('message', 'failed')}", file=sys.stderr)
    return 0 if doc.get("ok") else 1


def fail(output: str, message: str) -> int:
    return emit(output, {"ok": False, "error": {"message": message}})


def human_status(d: dict) -> str:
    if not d.get("configured"):
        return f"Not configured. Run: {APP} login"
    if not d.get("activity"):
        return "Connecting…" if d.get("connecting") else f"Not connected ({d.get('error') or 'unknown'})"
    lines = [
        f"{d.get('name') or d.get('model')}: {d.get('statusLabel')} · battery {d.get('battery')}%",
        f"Suction: {d.get('suctionLabel') or '-'}",
    ]
    if d.get("errorLabel"):
        lines.append(f"Error: {d['errorLabel']}")
    if d.get("currentRoom"):
        lines.append(f"Room: {d['currentRoom']}")
    if d.get("running"):
        lines.append(f"Cleaned: {d.get('cleanedArea')} m² in {d.get('cleaningTime')} min")
    return "\n".join(lines)


def client(args) -> int:
    out = args.output
    cmd = args.command
    lang = args.lang
    try:
        if cmd == "watch":
            with request("watch", lang=lang, timeout=None) as s:
                for line in s.makefile("rb"):
                    sys.stdout.write(line.decode())
                    sys.stdout.flush()
            return 0
        if cmd == "status":
            doc = call("status", lang=lang)
            return emit(out, doc, human_status(doc.get("data") or {}))
        if cmd == "rooms":
            doc = call("status", lang=lang)
            if doc.get("ok"):
                doc = {"ok": True, "data": (doc.get("data") or {}).get("rooms", [])}
            return emit(out, doc, "\n".join(f"{r['id']:>3}  {r['name']}" for r in doc.get("data") or []))
        payload = {}
        if cmd == "suction":
            payload = {"level": args.level}
        elif cmd == "clean-rooms":
            payload = {"rooms": args.rooms, "repeats": args.repeats}
        doc = call(cmd, payload, lang=lang)
        return emit(out, doc, "ok")
    except ConnectionError as ex:
        return fail(out, str(ex))
    except (OSError, ValueError) as ex:
        return fail(out, str(ex) or type(ex).__name__)
    except KeyboardInterrupt:
        return 130


# ---------------------------------------------------------------- login


def login(args) -> int:
    import_library()
    from dreame import DreameVacuumProtocol, DEVICE_INFO
    import base64
    import zlib

    cfg = load_config()
    account = args.account or cfg.get("account_type") or "dreame"
    if account not in ACCOUNT_TYPES:
        print(f"Account type must be one of: {', '.join(ACCOUNT_TYPES)}", file=sys.stderr)
        return 2
    if account == "mi":
        print("Xiaomi accounts need two-factor login; that is not supported here yet.", file=sys.stderr)
        return 2
    username = args.username or input(f"{account.capitalize()} account e-mail: ").strip()
    if args.password_stdin:
        password = sys.stdin.readline().rstrip("\n")
    else:
        password = getpass.getpass("Password: ")
    country = (args.country or cfg.get("country") or "eu").lower()
    if country not in COUNTRIES:
        print(f"Country/region must be one of: {', '.join(COUNTRIES)}", file=sys.stderr)
        return 2

    print("Logging in…", file=sys.stderr)
    protocol = DreameVacuumProtocol(
        username=username, password=password, country=country, prefer_cloud=True, account_type=account
    )
    try:
        protocol.cloud.login()
        if not protocol.cloud.logged_in:
            print("Login failed. Check the e-mail, password and region.", file=sys.stderr)
            return 1

        info = json.loads(zlib.decompress(base64.b64decode(DEVICE_INFO), zlib.MAX_WBITS | 32))
        models = {}
        prefix = {1: "xiaomi", 2: "mova", 3: "trouver"}
        for k in info[3]:
            entry = info[0][info[3][k]]
            if entry:
                models[f"{prefix.get(entry[0], 'dreame')}.vacuum.{k}"] = entry[1]
        devices, unsupported = protocol.cloud.get_supported_devices(models)
    finally:
        try:
            protocol.disconnect()
        except Exception:
            pass

    if not devices:
        extra = f" (unsupported: {', '.join(d.get('model', '?') for d in unsupported)})" if unsupported else ""
        print(f"No supported robot found on this account{extra}.", file=sys.stderr)
        return 1

    if len(devices) == 1:
        chosen = devices[0]
    else:
        for i, d in enumerate(devices, 1):
            print(f"  {i}. {d.get('name')} ({d.get('model')})")
        while True:
            pick = input(f"Which robot? [1-{len(devices)}]: ").strip()
            if pick.isdigit() and 1 <= int(pick) <= len(devices):
                chosen = devices[int(pick) - 1]
                break

    cfg.update(
        {
            "account_type": account,
            "username": username,
            "password": password,
            "country": country,
            "did": chosen.get("did"),
            "mac": chosen.get("mac"),
            "model": chosen.get("model"),
            "name": chosen.get("name") or chosen.get("model"),
            "host": chosen.get("bindDomain"),
            "token": " ",
            "auth_key": protocol.cloud.auth_key,
        }
    )
    save_config(cfg)
    print(f"Saved {cfg['name']} ({cfg['model']}) to {config_path()}", file=sys.stderr)
    print(f"Restart the daemon to use it: systemctl --user restart {APP}", file=sys.stderr)
    return 0


def logout(args) -> int:
    try:
        config_path().unlink()
    except FileNotFoundError:
        pass
    print(f"Removed {config_path()}", file=sys.stderr)
    return 0


# ---------------------------------------------------------------- main


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog=APP, description="Control a Dreame robot vacuum.")
    p.add_argument("--output", choices=("text", "json"), default="text")
    p.add_argument("--lang", default=(os.environ.get("LANG") or "en").split(".")[0].split("_")[0])
    p.add_argument("--version", action="version", version=f"{APP} {VERSION}")
    sub = p.add_subparsers(dest="command", required=True)

    sp = sub.add_parser("serve", help="run the daemon")
    sp.add_argument("-v", "--verbose", action="store_true")

    lp = sub.add_parser("login", help="log in and pick a robot")
    lp.add_argument("--account", choices=ACCOUNT_TYPES)
    lp.add_argument("--username")
    lp.add_argument("--country", choices=COUNTRIES)
    lp.add_argument("--password-stdin", action="store_true")
    sub.add_parser("logout", help="forget the saved account")

    sub.add_parser("status", help="show the robot's state")
    sub.add_parser("watch", help="print the state as JSON lines whenever it changes")
    sub.add_parser("rooms", help="list the rooms of the current map")
    for name, text in (
        ("start", "start or resume cleaning"),
        ("pause", "pause cleaning"),
        ("stop", "stop cleaning"),
        ("dock", "return to the dock"),
        ("locate", "make the robot say where it is"),
        ("toggle", "start, resume or pause"),
    ):
        sub.add_parser(name, help=text)
    su = sub.add_parser("suction", help="set the suction level")
    su.add_argument("level", choices=SUCTION_LEVELS)
    cr = sub.add_parser("clean-rooms", help="clean the given rooms (ids from `rooms`)")
    cr.add_argument("rooms", nargs="+", type=int)
    cr.add_argument("--repeats", type=int, default=1, choices=(1, 2, 3))

    args = p.parse_args(argv)
    if args.command == "serve":
        serve(args)
        return 0
    if args.command == "login":
        return login(args)
    if args.command == "logout":
        return logout(args)
    return client(args)


if __name__ == "__main__":
    sys.exit(main())
