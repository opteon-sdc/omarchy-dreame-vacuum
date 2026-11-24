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
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string barLabel: String(setting("barLabel", "cleaning"))
  readonly property bool notify: setting("notify", true) === true
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

  readonly property var st: svc.vac
  readonly property bool online: svc.online
  readonly property bool busy: st.running === true && st.paused !== true && st.returning !== true
  readonly property bool alerting: online && (st.hasError === true || st.hasWarning === true)

  // Room ids picked in the panel for a room clean.
  property var selectedRooms: []
  property int repeats: 1

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: svc
    settings: root.settings
    language: Commons.I18n.language || "en"
    onUpdated: function (previous, next) { root.announce(previous, next) }
  }

  // ---- notifications

  function announce(previous, next) {
    if (!notify || !previous || previous.activity === undefined || next.activity === undefined) return
    var name = next.name || "Dreame"
    if (next.hasError && !previous.hasError) {
      send(name, next.errorLabel || next.statusLabel, "critical")
      return
    }
    var wasCleaning = previous.running === true || previous.returning === true
    var home = next.docked === true || next.charging === true
    if (wasCleaning && home && !next.running) {
      send(name, tr("notify.finished", "Cleaning finished: %1 m² in %2 min")
        .arg(Commons.I18n.formatNumber(previous.cleanedArea || 0))
        .arg(Commons.I18n.formatNumber(previous.cleaningTime || 0)), "normal")
    }
  }

  function send(title, body, urgency) {
    Quickshell.execDetached(["notify-send", "--app-name=Dreame", "--icon=robot-vacuum", "--urgency=" + urgency, String(title), String(body)])
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
    svc.cleanRooms(selectedRooms, repeats)
    selectedRooms = []
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
      "not_connected": "error.notConnected"
    }
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
      onActivateRequested: if (root.online) svc.toggle()
      onTextKey: function (t) {
        if (!root.online) return
        var key = String(t).toLowerCase()
        var options = st.suctionOptions || []
        var level = options[Number(key) - 1]
        if (key === " " || key === "p") svc.toggle()
        else if (key === "s") svc.stop()
        else if (key === "h" || key === "d") svc.dock()
        else if (key === "l") svc.locate()
        else if (key >= "1" && key <= "4" && level && st.suctionAvailable) svc.setSuction(level.value)
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
            visible: root.alerting && (st.errorLabel || "") !== ""
            width: parent.width
            implicitHeight: bannerText.implicitHeight + Style.space(16)
            radius: Style.space(6)
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.15)
            border.width: 1
            border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.5)

            Label {
              id: bannerText
              anchors.fill: parent
              anchors.margins: Style.space(8)
              text: root.glyphAlert + "  " + (st.errorLabel || "")
              color: root.urgent
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
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

          // ---------- Current job ----------
          Column {
            visible: root.online && (st.running === true || st.paused === true)
            width: parent.width
            spacing: Style.spacing.labelGap
            InfoPair { label: root.tr("info.area", "Cleaned"); value: Commons.I18n.formatNumber(st.cleanedArea || 0) + " m²" }
            InfoPair { label: root.tr("info.time", "Time"); value: Commons.I18n.formatNumber(st.cleaningTime || 0) + " min" }
            InfoPair { visible: (st.cleaningModeLabel || "") !== ""; label: root.tr("info.mode", "Mode"); value: st.cleaningModeLabel || "" }
          }

          // ---------- Suction ----------
          Column {
            visible: root.online && (st.suctionOptions || []).length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: root.tr("section.suction", "Suction")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            ButtonGroup {
              width: parent.width
              options: st.suctionOptions || []
              value: st.suction || ""
              enabled: st.suctionAvailable !== false
              opacity: enabled ? 1 : 0.45
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              focusable: false
              onChanged: function (v) { svc.setSuction(v) }
            }
          }

          // ---------- Rooms ----------
          Column {
            visible: root.online && svc.rooms.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: root.tr("section.rooms", "Rooms")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

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

          // ---------- Map ----------
          // Two images take turns: a new render loads into the hidden one and
          // replaces the shown one only once it is fully decoded, so the map never blinks.
          Item {
            id: mapBox
            property bool showA: true
            property bool hasFrame: false
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
            onUrlChanged: load()
            Component.onCompleted: load()

            visible: root.showMap && root.online && hasFrame
            width: parent.width
            implicitHeight: visible ? Math.min(width, width * aspect) : 0
            Behavior on implicitHeight {
              enabled: mapBox.hasFrame
              NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
            }

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

          // ---------- Consumables ----------
          Column {
            visible: root.online && svc.consumables.length > 0
            width: parent.width
            spacing: Style.spacing.labelGap

            PanelSeparator { foreground: root.foreground }
            Item { width: 1; height: Style.space(4) }
            PanelSectionHeader {
              text: root.tr("section.maintenance", "Maintenance")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Item { width: 1; height: Style.space(4) }
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

          Label {
            visible: svc.lastError !== "" && root.online
            width: parent.width
            text: root.message(svc.lastError)
            color: root.urgent
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
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
