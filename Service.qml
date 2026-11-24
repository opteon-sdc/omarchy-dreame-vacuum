import QtQuick
import Quickshell
import Quickshell.Io

// Talks to the dreame-vacuum daemon: one long-running `watch` for state,
// and short client calls for commands, run one at a time.
Item {
  id: root

  property var settings: ({})
  property string language: "en"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  readonly property string cli: String(setting("cliPath", "dreame-vacuum"))

  // Last state from the daemon (see `dreame-vacuum --output json status`).
  property var vac: ({})
  property bool daemonUp: false
  property bool loaded: false
  property string lastError: ""
  property string pending: ""     // command waiting for an answer
  property int mapSerial: 0

  readonly property bool configured: vac.configured === true
  readonly property bool online: daemonUp && configured && vac.activity !== undefined
  readonly property var rooms: Array.isArray(vac.rooms) ? vac.rooms : []
  readonly property var consumables: Array.isArray(vac.consumables) ? vac.consumables : []

  signal updated(var previous, var next)

  function plain(s, max) {
    // Names come from the cloud; keep them out of rich text paths.
    return String(s === undefined || s === null ? "" : s).replace(/</g, "‹").replace(/>/g, "›").slice(0, max || 64)
  }

  function accept(doc) {
    if (!doc || doc.ok !== true || !doc.data || typeof doc.data !== "object") return
    var d = doc.data
    var next = {
      configured: d.configured === true,
      connecting: d.connecting === true,
      authFailed: d.authFailed === true,
      error: plain(d.error, 200),
      name: plain(d.name),
      model: plain(d.model),
      updated: Number(d.updated) || 0
    }
    if (typeof d.activity === "string") {
      next.connected = d.connected === true
      next.activity = plain(d.activity, 24)
      next.status = plain(d.status, 40)
      next.statusLabel = plain(d.statusLabel)
      next.taskStatusLabel = plain(d.taskStatusLabel)
      next.hasError = d.hasError === true
      next.hasWarning = d.hasWarning === true
      next.errorCode = plain(d.errorCode, 40)
      next.errorLabel = plain(d.errorLabel, 160)
      next.battery = Math.max(0, Math.min(100, Number(d.battery) || 0))
      next.charging = d.charging === true
      next.docked = d.docked === true
      next.running = d.running === true
      next.paused = d.paused === true
      next.returning = d.returning === true
      next.suction = plain(d.suction, 16)
      next.suctionLabel = plain(d.suctionLabel, 32)
      next.suctionAvailable = d.suctionAvailable !== false
      next.cleaningModeLabel = plain(d.cleaningModeLabel, 40)
      next.cleanedArea = Math.max(0, Number(d.cleanedArea) || 0)
      next.cleaningTime = Math.max(0, Number(d.cleaningTime) || 0)
      next.currentRoom = plain(d.currentRoom)
      var options = []
      var src = Array.isArray(d.suctionOptions) ? d.suctionOptions : []
      for (var i = 0; i < src.length && i < 8; i++)
        if (src[i] && /^[a-z_]{1,16}$/.test(String(src[i].value)))
          options.push({ value: String(src[i].value), label: plain(src[i].label, 32) })
      next.suctionOptions = options
      var rooms = []
      var rs = Array.isArray(d.rooms) ? d.rooms : []
      for (var j = 0; j < rs.length && rooms.length < 64; j++) {
        var id = Number(rs[j] && rs[j].id)
        if (!isFinite(id) || id < 0 || id > 100000 || Math.floor(id) !== id) continue
        rooms.push({ id: id, name: plain(rs[j].name) })
      }
      next.rooms = rooms
      var cons = []
      var cs = Array.isArray(d.consumables) ? d.consumables : []
      for (var k = 0; k < cs.length && k < 12; k++) {
        var p = Number(cs[k] && cs[k].percent)
        if (!isFinite(p)) continue
        cons.push({ key: plain(cs[k].key, 32), label: plain(cs[k].label, 48), percent: Math.max(0, Math.min(100, Math.round(p))) })
      }
      next.consumables = cons
      if (d.map && typeof d.map.path === "string" && /^\/[\w\/.\-]+\.png$/.test(d.map.path)) {
        next.mapPath = d.map.path
        mapSerial = Number(d.map.serial) || 0
      }
    }
    var previous = vac
    vac = next
    loaded = true
    updated(previous, next)
  }

  // ---- state stream

  function restartWatch() {
    watch.running = false
    watchRetry.restart()
  }

  Process {
    id: watch
    running: true
    command: ["bash", "-c", "exec \"$@\"", "dreame", root.cli, "--output", "json", "--lang", root.language, "watch"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        root.daemonUp = true
        root.lastError = ""
        var doc = null
        try { doc = JSON.parse(line) } catch (e) { return }
        root.accept(doc)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t !== "") root.lastError = t.split("\n").pop().replace(/^dreame-vacuum: /, "").slice(0, 200)
      }
    }
    onExited: function (code) {
      root.daemonUp = false
      root.loaded = true
      if (code === 127) root.lastError = "cli_missing"
      watchRetry.restart()
    }
  }

  Timer {
    id: watchRetry
    interval: 5000
    onTriggered: if (!watch.running) watch.running = true
  }

  onLanguageChanged: restartWatch()
  onCliChanged: restartWatch()

  // ---- commands

  property var _queue: []

  function command(args, done) {
    var q = _queue.slice()
    q.push({ args: args, done: done })
    _queue = q
    _next()
  }

  function _next() {
    if (cmd.running || _queue.length === 0) return
    var q = _queue.slice()
    var job = q.shift()
    _queue = q
    cmd.job = job
    pending = job.args[0]
    cmd.command = ["bash", "-c", "exec \"$@\"", "dreame", cli, "--output", "json", "--lang", language].concat(job.args)
    cmd.running = true
  }

  Process {
    id: cmd
    property var job: null
    stdout: StdioCollector { id: cmdOut; waitForEnd: true }
    onExited: function (code) {
      var job = cmd.job
      cmd.job = null
      root.pending = ""
      var doc = null
      try { doc = JSON.parse(String(cmdOut.text || "").trim().split("\n").pop()) } catch (e) {}
      var ok = code === 0 && doc && doc.ok === true
      var msg = ok ? "" : (doc && doc.error && doc.error.message ? root.plain(doc.error.message, 200) : (code === 127 ? "cli_missing" : "failed"))
      if (!ok) root.lastError = msg
      Qt.callLater(root._next)
      if (job && job.done) job.done(ok, msg)
    }
  }

  function start() { command(["start"]) }
  function pause() { command(["pause"]) }
  function stop() { command(["stop"]) }
  function dock() { command(["dock"]) }
  function locate() { command(["locate"]) }
  function toggle() { command(["toggle"]) }
  function setSuction(level) { command(["suction", String(level)]) }
  function cleanRooms(ids, repeats) {
    if (!ids || ids.length === 0) return
    var args = ["clean-rooms"]
    for (var i = 0; i < ids.length; i++) args.push(String(Math.floor(Number(ids[i]))))
    args.push("--repeats", String(Math.max(1, Math.min(3, Number(repeats) || 1))))
    command(args)
  }

  function startDaemon() {
    Quickshell.execDetached(["systemctl", "--user", "restart", "dreame-vacuum.service"])
    restartWatch()
  }
}
