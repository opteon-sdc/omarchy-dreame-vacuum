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
  // The daemon sends the notifications (once, whatever the number of bars);
  // tell it whether to and in which language.
  readonly property bool notify: setting("notify", true) === true
  function syncNotify() { command(["notify", notify ? "on" : "off"]) }
  onNotifyChanged: syncNotify()
  Component.onCompleted: syncNotify()

  // Last state from the daemon (see `dreame-vacuum --output json status`).
  property var vac: ({})
  property bool daemonUp: false
  property bool loaded: false
  property string lastError: ""
  property string pending: ""     // command waiting for an answer
  property string pendingArg: ""  // its first argument, e.g. the routine id
  // Why the last command failed; clears itself after a while.
  property string commandError: ""
  property int mapSerial: 0

  readonly property bool configured: vac.configured === true
  readonly property bool online: daemonUp && configured && vac.activity !== undefined
  readonly property var rooms: Array.isArray(vac.rooms) ? vac.rooms : []
  readonly property var consumables: Array.isArray(vac.consumables) ? vac.consumables : []
  readonly property var routines: Array.isArray(vac.routines) ? vac.routines : []

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
      next.cleaningMode = /^[a-z_]{0,32}$/.test(String(d.cleaningMode || "")) ? String(d.cleaningMode || "") : ""
      next.cleaningModeLabel = plain(d.cleaningModeLabel, 40)
      var modes = []
      var ms = Array.isArray(d.cleaningModeOptions) ? d.cleaningModeOptions : []
      for (var m = 0; m < ms.length && m < 8; m++)
        if (ms[m] && /^[a-z_]{1,32}$/.test(String(ms[m].value)))
          modes.push({ value: String(ms[m].value), label: plain(ms[m].label, 40) })
      next.cleaningModeOptions = modes
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
      var routines = []
      var rt = Array.isArray(d.routines) ? d.routines : []
      for (var r = 0; r < rt.length && routines.length < 24; r++) {
        var x = rt[r] || {}
        if (!/^[a-z0-9_-]{1,32}$/.test(String(x.id))) continue
        var names = []
        var missing = []
        var xr = Array.isArray(x.rooms) ? x.rooms : []
        var xm = Array.isArray(x.missing) ? x.missing : []
        for (var a = 0; a < xr.length && a < 32; a++) names.push(plain(xr[a]))
        for (var b = 0; b < xm.length && b < 32; b++) missing.push(plain(xm[b]))
        routines.push({
          id: String(x.id),
          name: plain(x.name),
          rooms: names,
          missing: missing,
          mode: /^[a-z_]{0,32}$/.test(String(x.mode || "")) ? String(x.mode || "") : "",
          modeLabel: plain(x.modeLabel, 40),
          suctionLabel: plain(x.suctionLabel, 32),
          repeats: Math.max(1, Math.min(3, Number(x.repeats) || 1))
        })
      }
      next.routines = routines
      next.customizedCleaning = d.customizedCleaning === true
      var j = d.job && typeof d.job === "object" ? d.job : {}
      var jobRooms = []
      var jr = Array.isArray(j.rooms) ? j.rooms : []
      for (var q = 0; q < jr.length && jobRooms.length < 64; q++) {
        var st = String(jr[q] && jr[q].state)
        if (["done", "current", "todo", "skipped"].indexOf(st) < 0) continue
        jobRooms.push({ name: plain(jr[q].name), state: st })
      }
      var details = []
      var jd = Array.isArray(j.details) ? j.details : []
      for (var w = 0; w < jd.length && w < 8; w++)
        details.push({ label: plain(jd[w] && jd[w].label, 48), value: plain(jd[w] && jd[w].value, 64) })
      var totals = []
      var jt = Array.isArray(j.totals) ? j.totals : []
      for (var u = 0; u < jt.length && u < 6; u++) {
        var tv = Number(jt[u] && jt[u].value)
        if (!isFinite(tv) || tv < 0) continue
        totals.push({ label: plain(jt[u].label, 48), value: tv, unit: plain(jt[u].unit, 8) })
      }
      var pr = Number(j.progress)
      next.job = {
        active: j.active === true,
        task: plain(j.task, 48),
        progress: j.progress !== null && j.progress !== undefined && isFinite(pr) ? Math.max(0, Math.min(100, Math.round(pr))) : -1,
        rooms: jobRooms,
        wholeHome: j.wholeHome === true,
        resumesAfterCharge: j.resumesAfterCharge === true,
        mopInstalled: j.mopInstalled === true ? true : (j.mopInstalled === false ? false : null),
        details: details,
        totals: totals
      }
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

  onLanguageChanged: { restartWatch(); syncNotify() }
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
    pendingArg = job.args.length > 1 ? String(job.args[1]) : ""
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
      root.pendingArg = ""
      var doc = null
      try { doc = JSON.parse(String(cmdOut.text || "").trim().split("\n").pop()) } catch (e) {}
      var ok = code === 0 && doc && doc.ok === true
      var msg = ok ? "" : (doc && doc.error && doc.error.message ? root.plain(doc.error.message, 200) : (code === 127 ? "cli_missing" : "failed"))
      root.commandError = ok ? "" : msg
      if (!ok) commandErrorClear.restart()
      Qt.callLater(root._next)
      if (job && job.done) job.done(ok, msg)
    }
  }

  Timer {
    id: commandErrorClear
    interval: 12000
    onTriggered: root.commandError = ""
  }

  function runRoutine(id) {
    if (/^[a-z0-9_-]{1,32}$/.test(String(id))) command(["routine", String(id)])
  }

  function start() { command(["start"]) }
  function pause() { command(["pause"]) }
  function stop() { command(["stop"]) }
  function dock() { command(["dock"]) }
  function locate() { command(["locate"]) }
  function toggle() { command(["toggle"]) }
  function setSuction(level) { command(["suction", String(level)]) }
  function cleanRooms(ids, repeats, mode, suction) {
    if (!ids || ids.length === 0) return
    var args = ["clean-rooms"]
    for (var i = 0; i < ids.length; i++) args.push(String(Math.floor(Number(ids[i]))))
    args.push("--repeats", String(Math.max(1, Math.min(3, Number(repeats) || 1))))
    if (/^[a-z_]{1,32}$/.test(String(mode || ""))) args.push("--mode", String(mode))
    if (/^[a-z_]{1,16}$/.test(String(suction || ""))) args.push("--suction", String(suction))
    command(args)
  }

  function startDaemon() {
    Quickshell.execDetached(["systemctl", "--user", "restart", "dreame-vacuum.service"])
    restartWatch()
  }
}
