import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.opteon-sdc.dreame"
  ipcTarget: "dreame"
  manageIpc: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  function tr(key, fallback) { return strings.t(key, fallback) }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color accentColor: Color.accent
  // Resolved here: inside an inline component `Color` does not reach the qs.Commons singleton.
  readonly property color panelBackground: Color.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string barLabel: String(setting("barLabel", "cleaning"))
  readonly property bool showMap: setting("showMap", true) === true
  readonly property int panelWidth: Math.max(340, Math.min(800, Number(setting("panelWidth", 420)) || 420))

  readonly property string glyphRobot: String.fromCodePoint(0xF070D)    // nf-md-robot_vacuum
  readonly property string glyphPlay: String.fromCodePoint(0xF040A)     // nf-md-play
  readonly property string glyphPause: String.fromCodePoint(0xF03E4)    // nf-md-pause
  readonly property string glyphStop: String.fromCodePoint(0xF04DB)     // nf-md-stop
  readonly property string glyphHome: String.fromCodePoint(0xF02DC)     // nf-md-home
  readonly property string glyphLocate: String.fromCodePoint(0xF01A4)   // nf-md-crosshairs_gps
  readonly property string glyphAlert: String.fromCodePoint(0xF0026)    // nf-md-alert
  readonly property string glyphRefresh: String.fromCodePoint(0xF0450)  // nf-md-refresh
  readonly property string glyphChecked: String.fromCodePoint(0xF0132)  // nf-md-checkbox_marked
  readonly property string glyphUnchecked: String.fromCodePoint(0xF0131) // nf-md-checkbox_blank_outline
  readonly property string glyphFan: String.fromCodePoint(0xF0210)      // nf-md-fan
  readonly property string glyphWater: String.fromCodePoint(0xF058C)    // nf-md-water
  readonly property string glyphThen: String.fromCodePoint(0xF0054)     // nf-md-arrow_right

  // Glyphs that say what a routine does: vacuum, mop, both, or mop after vacuuming.
  function modeGlyphs(mode) {
    if (mode === "sweeping") return glyphFan
    if (mode === "mopping") return glyphWater
    if (mode === "sweeping_and_mopping") return glyphFan + " " + glyphWater
    if (mode === "mopping_after_sweeping") return glyphFan + " " + glyphThen + " " + glyphWater
    return glyphRobot
  }

  readonly property var st: svc.vac
  readonly property bool online: svc.online
  readonly property bool busy: st.running === true && st.paused !== true && st.returning !== true
  // Only real errors are red; warnings (e.g. "clean the washboard") are reminders.
  readonly property bool alerting: online && st.hasError === true
  readonly property bool noticing: online && st.hasError !== true && st.hasWarning === true
  readonly property string glyphInfo: String.fromCodePoint(0xF02FD)        // nf-md-information_outline

  readonly property string glyphTabStatus: String.fromCodePoint(0xF0150)   // nf-md-clock_outline
  readonly property string glyphDone: String.fromCodePoint(0xF05E0)        // nf-md-check_circle
  readonly property string glyphTodo: String.fromCodePoint(0xF0766)        // nf-md-circle_outline
  readonly property string glyphSkipped: String.fromCodePoint(0xF04AD)     // nf-md-skip_next
  readonly property string glyphTabRoutines: String.fromCodePoint(0xF0411) // nf-md-playlist_play
  readonly property string glyphTabRooms: String.fromCodePoint(0xF0821)    // nf-md-floor_plan
  readonly property string glyphTabMap: String.fromCodePoint(0xF034D)      // nf-md-map
  readonly property string glyphTabCare: String.fromCodePoint(0xF05B7)     // nf-md-wrench
  readonly property string glyphZoomIn: String.fromCodePoint(0xF0349)      // nf-md-magnify_plus
  readonly property string glyphZoomOut: String.fromCodePoint(0xF034A)     // nf-md-magnify_minus
  readonly property string glyphFit: String.fromCodePoint(0xF0044)         // nf-md-arrow_collapse_all

  // Tabs with something to show; the last one picked is kept while the shell runs.
  property string tab: String(setting("defaultTab", "status"))
  readonly property var tabs: {
    var out = [{ value: "status", label: tr("section.status", "Status"), icon: glyphTabStatus }]
    if (svc.routines.length > 0) out.push({ value: "routines", label: tr("section.routines", "Routines"), icon: glyphTabRoutines })
    if (svc.rooms.length > 0) out.push({ value: "rooms", label: tr("section.rooms", "Rooms"), icon: glyphTabRooms })
    if (showMap && (st.mapPath || "") !== "") out.push({ value: "map", label: tr("section.map", "Map"), icon: glyphTabMap })
    if (svc.consumables.length > 0) out.push({ value: "care", label: tr("section.maintenance", "Maintenance"), icon: glyphTabCare })
    return out
  }
  readonly property string currentTab: {
    for (var i = 0; i < tabs.length; i++) if (tabs[i].value === tab) return tab
    return tabs.length > 0 ? tabs[0].value : ""
  }
  function cycleTab(step) {
    if (tabs.length < 2) return
    var at = 0
    for (var i = 0; i < tabs.length; i++) if (tabs[i].value === currentTab) at = i
    tab = tabs[(at + step + tabs.length) % tabs.length].value
  }

  // Room ids picked in the panel for a room clean.
  property var selectedRooms: []
  property int repeats: 1
  // Mode and suction for that clean; empty means "what the robot is set to now".
  property string pickMode: ""
  property string pickSuction: ""
  readonly property string roomMode: pickMode || st.cleaningMode || ""
  readonly property string roomSuction: pickSuction || st.suction || ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: svc
    settings: root.settings
    language: Commons.I18n.language || "en"
  }

  // ---- actions

  function toggleRoom(id) {
    var list = selectedRooms.slice()
    var at = list.indexOf(id)
    if (at >= 0) list.splice(at, 1)
    else list.push(id)
    selectedRooms = list
  }

  function cleanSelected() {
    if (selectedRooms.length === 0) return
    svc.cleanRooms(selectedRooms, repeats, roomMode, roomMode === "mopping" ? "" : roomSuction)
    selectedRooms = []
    pickMode = ""
    pickSuction = ""
  }

  function login() {
    // Values go in as positional arguments, never into the script text.
    Quickshell.execDetached(["xdg-terminal-exec", "bash", "-c",
      "\"$1\" login && systemctl --user restart dreame-vacuum.service; echo; read -rsn1 -p \"$2\"",
      "dreame", svc.cli, tr("login.pressKey", "Press a key to close")])
  }

  function message(key) {
    var s = String(key || "")
    if (s === "") return ""
    var known = {
      "daemon_not_running": "error.daemon",
      "cli_missing": "error.cli",
      "not_configured": "error.notConfigured",
      "auth_failed": "error.auth",
      "not_connected": "error.notConnected",
      "busy": "error.busy",
      "customized_cleaning": "error.customizedCleaning",
      "cleangenius": "error.cleanGenius"
    }
    if (s.indexOf("rooms_missing:") === 0)
      return tr("error.roomsMissing", "Not on the map: %1").arg(s.slice(14))
    return known[s] ? tr(known[s], s) : s
  }

  // `omarchy-shell dreame <function>`: the panel plus robot control, for keybindings.
  Commons.ShellIpc {
    target: "dreame"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function start(): void { svc.start() }
    function pause(): void { svc.pause() }
    function playPause(): void { svc.toggle() }
    function stop(): void { svc.stop() }
    function dock(): void { svc.dock() }
    function locate(): void { svc.locate() }
    function routine(id: string): void { svc.runRoutine(id) }
  }

  onOpenedChanged: if (opened) Qt.callLater(function () { keyCatcher.forceActiveFocus() })

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.alerting ? root.glyphAlert : root.glyphRobot
    labelText: {
      if (!root.online || button.vertical) return ""
      if (root.barLabel === "always" || (root.barLabel === "cleaning" && (root.busy || st.returning === true)))
        return Commons.I18n.formatNumber(st.battery) + "%"
      return ""
    }
    // Grow the slot by exactly the label, so the icon keeps the same margins as its neighbours.
    slotSize: Style.bar.iconSlot + (labelText !== "" ? Math.ceil(labelMetrics.advanceWidth) + Style.space(4) : 0)
    // Colour only means trouble; the battery label already says it is cleaning.
    active: root.alerting
    tooltipText: root.online ? (st.name + " · " + st.statusLabel) : ""
    onPressed: function (b) {
      if (b === Qt.MiddleButton) svc.toggle()
      else root.toggle()
    }
  }

  TextMetrics {
    id: labelMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    text: button.labelText
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(1100))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onMoveRequested: function (dx, dy) { if (dx !== 0) root.cycleTab(dx) }
      onActivateRequested: if (root.online) svc.toggle()
      onTextKey: function (t) {
        if (!root.online) return
        var key = String(t).toLowerCase()
        var routine = (st.routines || [])[Number(key) - 1]
        if (key === " " || key === "p") svc.toggle()
        else if (key === "s") svc.stop()
        else if (key === "h" || key === "d") svc.dock()
        else if (key === "l") svc.locate()
        else if (root.currentTab === "map" && (key === "+" || key === "=")) mapBox.zoomBy(1.5)
        else if (root.currentTab === "map" && key === "-") mapBox.zoomBy(1 / 1.5)
        else if (root.currentTab === "map" && key === "0") mapBox.reset()
        else if (key >= "1" && key <= "9" && routine && routine.missing.length === 0) svc.runRoutine(routine.id)
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: column
          width: parent.width
          spacing: Style.space(14)

          // ---------- Hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

            Label {
              id: heroIcon
              text: root.glyphRobot
              color: root.alerting ? root.urgent : root.foreground
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: heroPercent.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Label {
                width: parent.width
                text: st.name || root.tr("title", "Robot vacuum")
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Label {
                width: parent.width
                text: {
                  if (!svc.loaded) return root.tr("state.loading", "Loading…")
                  if (!svc.daemonUp) return root.tr("state.offline", "Service not running")
                  if (!svc.configured) return root.tr("state.notConfigured", "Not logged in")
                  if (!root.online) return st.connecting ? root.tr("state.connecting", "Connecting…") : root.tr("state.disconnected", "Not connected")
                  var s = st.statusLabel || ""
                  return (st.currentRoom && st.running ? s + " · " + st.currentRoom : s).toUpperCase()
                }
                color: root.dim
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }

            Label {
              id: heroPercent
              visible: root.online
              text: Commons.I18n.formatNumber(st.battery || 0) + "%"
              font.pixelSize: Style.font.displayLarge
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // ---------- Battery ----------
          Item {
            visible: root.online
            width: parent.width
            implicitHeight: Style.space(8)

            Rectangle {
              id: track
              anchors.fill: parent
              radius: height / 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            }
            Rectangle {
              anchors.left: track.left
              height: track.height
              radius: track.radius
              color: (st.battery || 0) <= 15 ? root.urgent : root.foreground
              width: Math.max(track.height, track.width * (st.battery || 0) / 100)
              Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }

              SequentialAnimation on opacity {
                running: st.charging === true && root.opened && !Style.reduceMotion
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { from: 1.0; to: 0.55; duration: Style.duration(950); easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.55; to: 1.0; duration: Style.duration(950); easing.type: Easing.InOutSine }
              }
            }
          }

          // ---------- Problem banner ----------
          Rectangle {
            readonly property color tone: root.alerting ? root.urgent : root.foreground
            visible: (root.alerting || root.noticing) && (st.errorLabel || "") !== ""
            width: parent.width
            implicitHeight: bannerText.implicitHeight + Style.space(16)
            radius: Style.space(6)
            color: Qt.rgba(tone.r, tone.g, tone.b, root.alerting ? 0.15 : 0.06)
            border.width: 1
            border.color: Qt.rgba(tone.r, tone.g, tone.b, root.alerting ? 0.5 : 0.18)

            Label {
              id: bannerText
              anchors.fill: parent
              anchors.margins: Style.space(8)
              text: (root.alerting ? root.glyphAlert : root.glyphInfo) + "  " + (st.errorLabel || "")
              color: root.alerting ? root.urgent : root.dim
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Label {
            visible: svc.commandError !== "" && root.online
            width: parent.width
            text: root.glyphAlert + "  " + root.message(svc.commandError)
            color: root.urgent
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ---------- Setup / offline ----------
          Column {
            visible: svc.loaded && !root.online
            width: parent.width
            spacing: Style.space(10)

            Label {
              width: parent.width
              wrapMode: Text.WordWrap
              color: root.dim
              font.pixelSize: Style.font.bodySmall
              text: {
                if (!svc.daemonUp) return root.message(svc.lastError || "daemon_not_running")
                if (!svc.configured) return root.tr("error.notConfigured", "Log in with your Dreamehome account to get started.")
                if (st.authFailed) return root.tr("error.auth", "Login was refused. Log in again.")
                return st.connecting ? root.tr("state.connectingLong", "Connecting to the Dreame cloud…") : root.message(st.error)
              }
            }

            Row {
              spacing: Style.space(8)
              Button {
                visible: svc.lastError !== "cli_missing"
                iconText: root.glyphRobot
                text: root.tr("action.login", "Log in")
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.login()
              }
              Button {
                iconText: root.glyphRefresh
                text: root.tr("action.restart", "Restart service")
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: svc.startDaemon()
              }
            }
          }

          // ---------- Controls ----------
          Row {
            id: controls
            visible: root.online
            width: parent.width
            spacing: Style.space(6)
            readonly property real cell: (width - spacing * 3) / 4

            Button {
              width: controls.cell
              iconText: root.busy ? root.glyphPause : root.glyphPlay
              iconSize: Style.font.title
              text: root.busy ? root.tr("action.pause", "Pause") : (st.paused ? root.tr("action.resume", "Resume") : root.tr("action.start", "Start"))
              tooltipText: root.tr("key.toggle", "Space")
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              active: root.busy
              onClicked: svc.toggle()
            }
            Button {
              width: controls.cell
              iconText: root.glyphStop
              iconSize: Style.font.title
              text: root.tr("action.stop", "Stop")
              tooltipText: "S"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              enabled: st.running === true || st.paused === true || st.returning === true
              opacity: enabled ? 1 : 0.45
              onClicked: svc.stop()
            }
            Button {
              width: controls.cell
              iconText: root.glyphHome
              iconSize: Style.font.title
              text: root.tr("action.dock", "Dock")
              tooltipText: "H"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              active: st.returning === true
              enabled: st.docked !== true || st.returning === true
              opacity: enabled ? 1 : 0.45
              onClicked: svc.dock()
            }
            Button {
              width: controls.cell
              iconText: root.glyphLocate
              iconSize: Style.font.title
              text: root.tr("action.locate", "Locate")
              tooltipText: "L"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              onClicked: svc.locate()
            }
          }

          // ---------- Tabs ----------
          PanelSeparator { visible: root.online && root.tabs.length > 0; foreground: root.foreground }

          // Measures the tabs as text; when they do not fit, show icons with tooltips.
          ButtonGroup {
            id: tabMeasure
            visible: false
            options: root.tabs.map(function (t) { return { value: t.value, label: t.label } })
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
          }

          ButtonGroup {
            readonly property bool fits: tabMeasure.implicitWidth <= width
            visible: root.online && root.tabs.length > 1
            width: parent.width
            options: root.tabs.map(function (t) {
              return fits ? { value: t.value, label: t.label } : { value: t.value, label: "", icon: t.icon, tooltip: t.label }
            })
            value: root.currentTab
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function (v) { root.tab = v }
          }

          // Status: the job in progress, room by room, and the dock.
          Column {
            readonly property var job: st.job || ({})
            visible: root.online && root.currentTab === "status"
            width: parent.width
            spacing: Style.space(12)

            Label {
              visible: !parent.job.active
              width: parent.width
              text: st.docked ? root.tr("status.idleDocked", "No job running. The robot is in its dock.") : root.tr("status.idle", "No job running.")
              color: root.dim
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            // Task and progress
            Column {
              visible: parent.job.active === true
              width: parent.width
              spacing: Style.space(6)

              Item {
                width: parent.width
                implicitHeight: Math.max(taskText.implicitHeight, progressText.implicitHeight)
                Label {
                  id: taskText
                  anchors.left: parent.left
                  anchors.right: progressText.left
                  anchors.rightMargin: Style.space(8)
                  elide: Text.ElideRight
                  text: (st.job && st.job.task) || st.statusLabel || ""
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Label {
                  id: progressText
                  anchors.right: parent.right
                  visible: st.job && st.job.progress >= 0
                  text: Commons.I18n.formatNumber(st.job ? st.job.progress : 0) + "%"
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }

              Item {
                visible: st.job && st.job.progress >= 0
                width: parent.width
                implicitHeight: Style.space(6)
                Rectangle {
                  id: jobTrack
                  anchors.fill: parent
                  radius: height / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                }
                Rectangle {
                  height: jobTrack.height
                  radius: jobTrack.radius
                  color: root.accentColor
                  width: Math.max(jobTrack.height, jobTrack.width * Math.max(0, st.job ? st.job.progress : 0) / 100)
                  Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
                }
              }

              Label {
                visible: st.job && st.job.resumesAfterCharge === true
                width: parent.width
                text: root.tr("status.resumes", "Charging; cleaning resumes on its own once the battery is charged.")
                color: root.dim
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            // Numbers for this job
            Column {
              visible: parent.job.active === true
              width: parent.width
              spacing: Style.spacing.labelGap
              InfoPair { label: root.tr("info.area", "Cleaned"); value: Commons.I18n.formatNumber(st.cleanedArea || 0) + " m²" }
              InfoPair { label: root.tr("info.time", "Time"); value: Commons.I18n.formatNumber(st.cleaningTime || 0) + " min" }
              InfoPair { visible: (st.cleaningModeLabel || "") !== ""; label: root.tr("info.mode", "Mode"); value: st.cleaningModeLabel || "" }
              InfoPair { visible: (st.suctionLabel || "") !== ""; label: root.tr("section.suction", "Suction"); value: st.suctionLabel || "" }
              InfoPair {
                visible: st.job && st.job.mopInstalled !== null
                label: root.tr("status.mop", "Mop pads")
                value: st.job && st.job.mopInstalled ? root.tr("status.mopOn", "Attached") : root.tr("status.mopOff", "Not attached")
              }
              Repeater {
                model: st.job ? st.job.details : []
                InfoPair {
                  required property var modelData
                  label: modelData.label
                  value: modelData.value
                }
              }
            }

            // Rooms in this job
            Column {
              visible: parent.job.active === true && ((st.job.rooms || []).length > 0 || st.job.wholeHome)
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: root.tr("status.rooms", "Rooms in this job")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Label {
                visible: st.job && st.job.wholeHome && (st.job.rooms || []).length === 0
                text: root.tr("status.wholeHome", "Whole home")
                font.pixelSize: Style.font.bodySmall
              }
              Repeater {
                model: st.job ? st.job.rooms : []
                Item {
                  required property var modelData
                  width: parent.width
                  implicitHeight: roomName.implicitHeight
                  readonly property bool isCurrent: modelData.state === "current"

                  Label {
                    id: roomIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(20)
                    text: modelData.state === "done" ? root.glyphDone
                      : modelData.state === "current" ? root.glyphRobot
                      : modelData.state === "skipped" ? root.glyphSkipped : root.glyphTodo
                    color: parent.isCurrent ? root.accentColor : (modelData.state === "todo" ? root.dim : root.foreground)
                    font.pixelSize: Style.font.bodySmall
                    SequentialAnimation on opacity {
                      running: parent.isCurrent && root.opened && !Style.reduceMotion
                      loops: Animation.Infinite
                      alwaysRunToEnd: true
                      NumberAnimation { from: 1.0; to: 0.4; duration: Style.duration(900); easing.type: Easing.InOutSine }
                      NumberAnimation { from: 0.4; to: 1.0; duration: Style.duration(900); easing.type: Easing.InOutSine }
                    }
                  }
                  Label {
                    id: roomName
                    anchors.left: roomIcon.right
                    anchors.right: roomState.left
                    anchors.rightMargin: Style.space(8)
                    elide: Text.ElideRight
                    text: modelData.name
                    font.pixelSize: Style.font.bodySmall
                    font.bold: parent.isCurrent
                    color: modelData.state === "todo" ? root.dim : root.foreground
                  }
                  Label {
                    id: roomState
                    anchors.right: parent.right
                    text: root.tr("status.room." + modelData.state, modelData.state)
                    color: parent.isCurrent ? root.accentColor : root.dim
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // Lifetime
            Column {
              visible: (st.job && st.job.totals || []).length > 0
              width: parent.width
              spacing: Style.spacing.labelGap

              PanelSectionHeader {
                text: root.tr("status.totals", "All time")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Item { width: 1; height: Style.space(2) }
              Repeater {
                model: st.job ? st.job.totals : []
                InfoPair {
                  required property var modelData
                  label: modelData.label
                  value: Commons.I18n.formatNumber(modelData.value) + (modelData.unit ? " " + modelData.unit : "")
                }
              }
            }
          }

          // Routines
          Column {
            visible: root.online && root.currentTab === "routines"
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: st.routines || []
              RoutineCard {
                required property var modelData
                required property int index
                routine: modelData
                shortcut: index < 9 ? String(index + 1) : ""
              }
            }
          }

          // Rooms
          Column {
            visible: root.online && root.currentTab === "rooms"
            width: parent.width
            spacing: Style.space(10)

            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: st.rooms || []
                Button {
                  required property var modelData
                  readonly property bool picked: root.selectedRooms.indexOf(modelData.id) >= 0
                  iconText: picked ? root.glyphChecked : root.glyphUnchecked
                  text: modelData.name
                  fontSize: Style.font.bodySmall
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  selected: picked
                  active: (st.currentRoom || "") === modelData.name && st.running === true
                  onClicked: root.toggleRoom(modelData.id)
                }
              }
            }

            // How to clean the picked rooms.
            Column {
              visible: root.selectedRooms.length > 0 && (st.cleaningModeOptions || []).length > 0
              width: parent.width
              spacing: Style.space(6)
              PanelSectionHeader {
                text: root.tr("info.mode", "Mode")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Flow {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: st.cleaningModeOptions || []
                  Button {
                    required property var modelData
                    iconText: root.modeGlyphs(modelData.value)
                    text: modelData.label
                    fontSize: Style.font.bodySmall
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    bordered: true
                    selected: root.roomMode === modelData.value
                    onClicked: root.pickMode = modelData.value
                  }
                }
              }
            }

            Column {
              visible: root.selectedRooms.length > 0 && root.roomMode !== "mopping"
                && st.suctionAvailable !== false && (st.suctionOptions || []).length > 0
              width: parent.width
              spacing: Style.space(6)
              PanelSectionHeader {
                text: root.tr("section.suction", "Suction")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              ButtonGroup {
                width: parent.width
                options: st.suctionOptions || []
                value: root.roomSuction
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                focusable: false
                onChanged: function (v) { root.pickSuction = v }
              }
            }

            Row {
              visible: root.selectedRooms.length > 0
              spacing: Style.space(8)

              ButtonGroup {
                anchors.verticalCenter: parent.verticalCenter
                options: [{ value: "1", label: "1×" }, { value: "2", label: "2×" }, { value: "3", label: "3×" }]
                value: String(root.repeats)
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                focusable: false
                onChanged: function (v) { root.repeats = Number(v) }
              }
              Button {
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.glyphPlay
                text: strings.tn("action.cleanRooms", root.selectedRooms.length).arg(Commons.I18n.formatNumber(root.selectedRooms.length))
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                active: true
                onClicked: root.cleanSelected()
              }
            }
          }

          // Map: wheel or pinch to zoom around the pointer, drag to pan,
          // double-click to zoom in or back out. Two images take turns so a
          // new render replaces the old one only once it is decoded: no blinking,
          // and the zoom and position stay put while the robot moves.
          Item {
            id: mapBox
            property bool showA: true
            property bool hasFrame: false
            property real zoom: 1
            property real pinchBase: 1
            readonly property real maxZoom: 4
            readonly property Image front: showA ? mapA : mapB
            readonly property Image back: showA ? mapB : mapA
            // A new query string makes the Image read the re-rendered file.
            readonly property string url: root.showMap && root.opened && (st.mapPath || "") !== ""
              ? "file://" + st.mapPath + "?v=" + svc.mapSerial : ""
            readonly property real aspect: front.implicitWidth > 0 ? front.implicitHeight / front.implicitWidth : 1

            function load() {
              if (url === "" || front.source.toString() === url || back.source.toString() === url) return
              back.source = url
            }
            function swapIfReady(img) {
              if (img !== back || img.status !== Image.Ready) return
              showA = !showA
              hasFrame = true
            }
            // Zoom so the map point under (x, y) stays under (x, y).
            function zoomAt(z, x, y) {
              z = Math.max(1, Math.min(maxZoom, z))
              if (Math.abs(z - zoom) < 0.001) return
              var cx = (mapFlick.contentX + x) / zoom
              var cy = (mapFlick.contentY + y) / zoom
              zoom = z
              mapFlick.contentX = Math.max(0, Math.min(width * z - width, cx * z - x))
              mapFlick.contentY = Math.max(0, Math.min(height * z - height, cy * z - y))
            }
            function zoomBy(factor) { zoomAt(zoom * factor, width / 2, height / 2) }
            function reset() { zoomAt(1, width / 2, height / 2) }

            onUrlChanged: load()
            Component.onCompleted: load()

            visible: root.online && root.currentTab === "map"
            width: parent.width
            implicitHeight: hasFrame ? Math.min(width * aspect, Style.space(560)) : Style.space(120)

            Label {
              anchors.centerIn: parent
              visible: !mapBox.hasFrame
              text: root.tr("state.loadingMap", "Loading the map…")
              color: root.dim
              font.pixelSize: Style.font.bodySmall
            }

            Flickable {
              id: mapFlick
              anchors.fill: parent
              clip: true
              contentWidth: width * mapBox.zoom
              contentHeight: height * mapBox.zoom
              interactive: mapBox.zoom > 1
              boundsBehavior: Flickable.StopAtBounds

              Item {
                width: mapFlick.contentWidth
                height: mapFlick.contentHeight

                Image {
                  id: mapA
                  anchors.fill: parent
                  asynchronous: true
                  cache: false
                  smooth: true
                  mipmap: true
                  fillMode: Image.PreserveAspectFit
                  visible: mapBox.showA
                  onStatusChanged: mapBox.swapIfReady(mapA)
                }
                Image {
                  id: mapB
                  anchors.fill: parent
                  asynchronous: true
                  cache: false
                  smooth: true
                  mipmap: true
                  fillMode: Image.PreserveAspectFit
                  visible: !mapBox.showA
                  onStatusChanged: mapBox.swapIfReady(mapB)
                }
              }
            }

            WheelHandler {
              target: null
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function (event) {
                var steps = event.angleDelta.y / 120
                if (steps === 0) return
                mapBox.zoomAt(mapBox.zoom * Math.pow(1.2, steps), point.position.x, point.position.y)
              }
            }

            PinchHandler {
              target: null
              onActiveChanged: if (active) mapBox.pinchBase = mapBox.zoom
              onActiveScaleChanged: mapBox.zoomAt(mapBox.pinchBase * activeScale, centroid.position.x, centroid.position.y)
            }

            TapHandler {
              onDoubleTapped: function (eventPoint) {
                if (mapBox.zoom > 1.01) mapBox.reset()
                else mapBox.zoomAt(2.5, eventPoint.position.x, eventPoint.position.y)
              }
            }

            Column {
              visible: mapBox.hasFrame
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.space(6)
              spacing: Style.space(4)

              MapButton { glyph: root.glyphZoomIn; tip: root.tr("map.zoomIn", "Zoom in (+)"); onClicked: mapBox.zoomBy(1.5) }
              MapButton { glyph: root.glyphZoomOut; tip: root.tr("map.zoomOut", "Zoom out (−)"); enabled: mapBox.zoom > 1; onClicked: mapBox.zoomBy(1 / 1.5) }
              MapButton { glyph: root.glyphFit; tip: root.tr("map.fit", "Whole map (0)"); enabled: mapBox.zoom > 1; onClicked: mapBox.reset() }
            }

            Rectangle {
              visible: mapBox.zoom > 1.01
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(6)
              width: zoomText.implicitWidth + Style.space(12)
              height: zoomText.implicitHeight + Style.space(6)
              radius: height / 2
              color: Qt.rgba(root.panelBackground.r, root.panelBackground.g, root.panelBackground.b, 0.85)

              Label {
                id: zoomText
                anchors.centerIn: parent
                text: Commons.I18n.formatNumber(Math.round(mapBox.zoom * 10) / 10, 1) + "×"
                font.pixelSize: Style.font.caption
              }
            }
          }

          // Maintenance
          Column {
            visible: root.online && root.currentTab === "care"
            width: parent.width
            spacing: Style.spacing.labelGap

            Repeater {
              model: st.consumables || []
              InfoPair {
                required property var modelData
                label: modelData.label
                value: Commons.I18n.formatNumber(modelData.percent) + "%"
                warn: modelData.percent <= 10
              }
            }
          }
        }
      }
    }
  }

  component MapButton: Rectangle {
    id: mb
    property string glyph: ""
    property string tip: ""
    signal clicked()
    width: Style.space(28)
    height: width
    radius: Style.space(6)
    color: Qt.rgba(root.panelBackground.r, root.panelBackground.g, root.panelBackground.b, mbMouse.containsMouse && mb.enabled ? 0.95 : 0.8)
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, mbMouse.containsMouse && mb.enabled ? 0.5 : 0.2)
    opacity: enabled ? 1 : 0.4

    Label {
      anchors.centerIn: parent
      text: mb.glyph
      font.pixelSize: Style.font.body
    }
    MouseArea {
      id: mbMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: mb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (mb.enabled) mb.clicked()
    }
  }

  component RoutineCard: Rectangle {
    id: card
    property var routine: ({})
    property string shortcut: ""
    readonly property bool runnable: (routine.missing || []).length === 0 && svc.pending === ""
    readonly property bool starting: svc.pending === "routine" && svc.pendingArg === routine.id
    readonly property bool hot: cardMouse.containsMouse && runnable

    width: parent ? parent.width : 0
    implicitHeight: cardText.implicitHeight + Style.space(18)
    radius: Style.space(6)
    color: hot ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, hot ? 0.45 : 0.18)
    opacity: (routine.missing || []).length > 0 ? 0.5 : (starting ? 0.7 : 1)
    scale: cardMouse.pressed && runnable ? 0.98 : 1
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

    Column {
      id: cardText
      anchors.left: parent.left
      anchors.right: modeIcon.left
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Label {
        width: parent.width
        text: (card.shortcut !== "" ? card.shortcut + "  " : "") + (card.routine.name || "")
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }
      Label {
        width: parent.width
        text: {
          var r = card.routine
          if ((r.missing || []).length > 0) return root.tr("error.roomsMissing", "Not on the map: %1").arg(r.missing.join(", "))
          var parts = [(r.rooms || []).join(", ")]
          if (r.modeLabel) parts.push(r.modeLabel)
          if (r.suctionLabel) parts.push(r.suctionLabel)
          if (r.repeats > 1) parts.push(r.repeats + "×")
          return parts.join(" · ")
        }
        color: root.dim
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    Label {
      id: modeIcon
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: card.starting ? root.glyphRefresh : root.modeGlyphs(card.routine.mode)
      color: card.hot ? root.accentColor : root.foreground
      font.pixelSize: Style.font.body
      RotationAnimation on rotation {
        running: card.starting && !Style.reduceMotion
        from: 0; to: 360; duration: 900; loops: Animation.Infinite
      }
      rotation: 0
    }

    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: card.runnable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (card.runnable) svc.runRoutine(card.routine.id)
    }
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  component InfoPair: Item {
    property string label: ""
    property string value: ""
    property bool warn: false
    width: parent ? parent.width : 0
    implicitHeight: Math.max(pairLabel.implicitHeight, pairValue.implicitHeight)

    Text {
      id: pairLabel
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: pairValue.left
      anchors.rightMargin: Style.space(8)
      elide: Text.ElideRight
      text: parent.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      id: pairValue
      textFormat: Text.PlainText
      anchors.right: parent.right
      text: parent.value
      color: parent.warn ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
