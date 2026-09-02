import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Commands.js" as Commands

// Full-screen command surface for Duolingo. Mirrors the architecture of
// ryanyogan.hydrate's Overlay.qml which is proven on this system:
// PanelWindow with WlrLayershell Overlay/Exclusive, open(payloadJson) that
// resolves the focused screen, and finishClose() that MUST call shell.hide(id).
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  // ---------------------------------------------------------------- theming

  readonly property color ink: "white"
  readonly property color background: Color.background
  readonly property color accent: Color.accent || "#58cc02"
  readonly property color urgent: Color.urgent
  readonly property color dim: Util.alpha(ink, 0.62)
  readonly property color faint: Util.alpha(ink, 0.42)
  readonly property color muted: Util.alpha(ink, 0.32)
  readonly property color hairline: Util.alpha(ink, 0.12)
  readonly property color fill: Util.alpha(ink, 0.07)
  readonly property string fontFamily: Style.font.family

  // Duolingo green family — use accent when available, fallback to #58cc02
  readonly property color duoGreen: accent
  readonly property color duoDone: duoGreen
  readonly property color water: goalMet ? duoDone : duoGreen
  readonly property color heroText: goalMet ? duoDone : ink

  readonly property bool reducedMotion: service ? service.reducedMotion === true : false
  readonly property bool animated: opened && !reducedMotion

  readonly property int motionFast: 140
  readonly property int motionBase: 220
  readonly property int motionSlow: 320

  // ---------------------------------------------------------------- derived state

  readonly property bool ready: service ? (service.userData && service.userData.valid) : false
  readonly property var userData: service ? service.userData : null
  readonly property int goalXp: service ? service.goalXp : 50
  readonly property int xpToday: service ? service.xpToday : 0
  readonly property real fraction: service ? service.goalFraction : 0
  readonly property bool goalMet: service ? service.goalMet === true : false
  readonly property int streak: userData && userData.valid ? (Number(userData.streak) || 0) : 0
  readonly property bool streakExtendedToday: userData && userData.valid ? !!userData.streakExtendedToday : false
  readonly property var weekData: service ? service.weekHistory : Model.weekHistory(null)
  readonly property bool hasHistory: service && service.history && service.history.days && Object.keys(service.history.days).length > 0

  readonly property string headline: {
    if (!ready) return "Duolingo"
    if (goalMet) return "Goal met"
    if (xpToday === 0) return "Nothing yet today"
    var remain = goalXp - xpToday
    if (remain <= 10) return "Almost there"
    return remain + " XP to go"
  }

  readonly property string dateLine: {
    var d = new Date()
    var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    return days[d.getDay()] + ", " + (d.getMonth() + 1) + "/" + d.getDate()
  }

  readonly property string statusLine: {
    if (!ready) return "No data yet — run refresh or set your username"
    if (streakExtendedToday) return "Streak kept alive today"
    return "Daily lesson pending — keep your streak going"
  }

  property string pane: "today" // today | history | help
  property string toast: ""
  property bool toastError: false

  // History for panes, built only while open
  readonly property var pastDays: {
    if (!opened || !service || !service.history || !service.history.days) return []
    var days = service.history.days
    var keysAsc = Object.keys(days).sort()
    var keysDesc = keysAsc.slice().reverse()
    var todayK = Model.dayKey(new Date())
    var out = []
    for (var i = 0; i < keysDesc.length && out.length < 14; i++) {
      var k = keysDesc[i]
      if (k === todayK) continue
      var entry = days[k]
      if (!entry) continue
      // xpEarned delta vs prior day in sorted order
      var idx = keysAsc.indexOf(k)
      var prior = null
      for (var j = idx - 1; j >= 0; j--) { if (keysAsc[j] < k) { prior = keysAsc[j]; break } }
      var xpEarned = 0
      if (prior !== null) {
        var cur = Number(entry.totalXp) || 0
        var prev = Number(days[prior].totalXp) || 0
        var diff = cur - prev
        xpEarned = diff > 0 ? diff : 0
      }
      // label like "2026-09-01" -> "Mon 09/01"
      var d = Model.keyToDate(k)
      var wdays = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
      var label = wdays[d.getDay()] + " " + (d.getMonth()+1) + "/" + d.getDate()
      out.push({ key: k, label: label, streak: Number(entry.streak)||0, xpEarned: xpEarned, totalXp: Number(entry.totalXp)||0, fraction: Model.fraction(xpEarned, goalXp) })
    }
    return out
  }

  // ---------------------------------------------------------------- lifecycle

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (String(screens[i].name || "") === name) return screens[i]
    return null
  }

  function open(payloadJson) {
    if (!service && shell && typeof shell.serviceFor === "function") service = shell.serviceFor("user.duolingo")
    var screen = focusedScreen()
    if (screen) panel.screen = screen
    exit.stop()
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    if (!opened) {
      opened = true
      pane = "today"
      toast = ""
      cmd.text = ""
      if (animated) enter.restart()
    }
    if (payload.pane) {
      var p = String(payload.pane)
      if (p === "today" || p === "history" || p === "help") pane = p
    }
    if (payload.cmd) cmd.text = String(payload.cmd)
    Qt.callLater(function() { if (root.opened) cmd.forceActiveFocus() })
  }

  function close() {
    if (!opened) return
    opened = false
    if (animated || exit.running) exit.restart()
    else finishClose()
  }

  function finishClose() {
    if (shell && typeof shell.hide === "function") Qt.callLater(function() { shell.hide("user.duolingo") })
  }

  function toggle() { opened ? close() : open("{}") }

  // ---------------------------------------------------------------- commands

  readonly property var ctx: Commands.contextOf(service)
  readonly property var suggestions: opened ? Commands.suggest(cmd.text, ctx, 6) : []

  Connections {
    target: root.service
    function onRequestOverlayClose() { root.close() }
  }
  property int selected: 0
  readonly property string ghost: {
    if (!cmd.text.length || !suggestions.length) return ""
    var c = suggestions[Math.min(selected, suggestions.length - 1)].completion
    var typed = cmd.text.toLowerCase()
    return c.toLowerCase().indexOf(typed) === 0 ? c.slice(typed.length) : ""
  }
  readonly property var livePreview: cmd.text.length ? Commands.parse(cmd.text, ctx) : null
  onSuggestionsChanged: selected = 0

  function accept() {
    if (!suggestions.length) return
    cmd.text = suggestions[Math.min(selected, suggestions.length - 1)].completion
    cmd.cursorPosition = cmd.text.length
  }

  function submit() {
    var line = cmd.text.trim()
    if (!line) { if (suggestions.length) { cmd.text = suggestions[selected].completion; cmd.cursorPosition = cmd.text.length } return }
    var parsed = Commands.parse(line, ctx)
    if (!parsed.ok) { showToast(parsed.error || "Nothing to do", true); shake.restart(); return }
    if (parsed.ui) {
      if (parsed.ui === "close") { close(); return }
      if (parsed.ui === "open") { service.requestPanelOpen(); close(); return }
      pane = parsed.ui
      cmd.text = ""
      return
    }
    var msg = Commands.execute(service, parsed)
    showToast(msg, false)
    cmd.text = ""
    sent.restart()
  }

  function showToast(text, isError) {
    toast = text
    toastError = isError === true
    toastTimer.restart()
  }
  Timer { id: toastTimer; interval: 2200; onTriggered: root.toast = "" }

  function handleKey(event) {
    switch (event.key) {
    case Qt.Key_Escape:
      if (cmd.text.length) cmd.text = ""
      else close()
      event.accepted = true; break
    case Qt.Key_Return: case Qt.Key_Enter:
      submit(); event.accepted = true; break
    case Qt.Key_Tab:
      accept(); event.accepted = true; break
    case Qt.Key_Down:
      if (suggestions.length) selected = (selected + 1) % suggestions.length
      event.accepted = true; break
    case Qt.Key_Up:
      if (suggestions.length) selected = (selected + suggestions.length - 1) % suggestions.length
      event.accepted = true; break
    case Qt.Key_PageDown: case Qt.Key_PageUp:
      var panes = ["today", "history", "help"]
      var i = panes.indexOf(pane)
      pane = panes[(i + (event.key === Qt.Key_PageDown ? 1 : panes.length - 1)) % panes.length]
      event.accepted = true; break
    }
  }

  // ---------------------------------------------------------------- motion

  ParallelAnimation {
    id: enter
    NumberAnimation { target: scrim; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    SequentialAnimation {
      PauseAnimation { duration: 40 }
      NumberAnimation { target: content; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
    }
    SpringAnimation { target: content; property: "scale"; from: 0.96; to: 1; spring: 3.2; damping: 0.28; mass: 1; epsilon: 0.005 }
    SequentialAnimation {
      PauseAnimation { duration: 200 }
      ScriptAction { script: { dial.ignite(); } }
    }
  }

  SequentialAnimation {
    id: exit
    ParallelAnimation {
      NumberAnimation { target: content; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
      NumberAnimation { target: content; property: "scale"; to: 0.985; duration: 140; easing.type: Easing.InCubic }
      NumberAnimation { target: scrim; property: "opacity"; to: 0; duration: 200; easing.type: Easing.OutCubic }
    }
    ScriptAction { script: root.finishClose() }
  }

  SequentialAnimation {
    id: sent
    NumberAnimation { target: cmdBox; property: "opacity"; to: 0.4; duration: 60 }
    NumberAnimation { target: cmdBox; property: "opacity"; to: 1; duration: root.motionFast }
  }
  SequentialAnimation {
    id: shake
    NumberAnimation { target: cmdBox; property: "anchors.horizontalCenterOffset"; to: -Style.space(6); duration: 45 }
    NumberAnimation { target: cmdBox; property: "anchors.horizontalCenterOffset"; to: Style.space(6); duration: 90 }
    NumberAnimation { target: cmdBox; property: "anchors.horizontalCenterOffset"; to: 0; duration: 45 }
  }

  // ---------------------------------------------------------------- window

  PanelWindow {
    id: panel
    visible: root.opened || exit.running
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "duolingo-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    Rectangle {
      id: scrim
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.78)
      opacity: root.reducedMotion ? 1 : 0
      MouseArea { anchors.fill: parent; enabled: root.opened; onClicked: root.close() }

      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 1.0; color: Util.alpha(root.duoGreen, 0.14) }
        }
      }
    }

    Item {
      id: content
      anchors.centerIn: parent
      width: Math.min(panel.width - Style.space(80), Style.space(1180))
      height: Math.min(panel.height - Style.space(80), Style.space(760))
      opacity: root.reducedMotion ? 1 : 0
      scale: root.reducedMotion ? 1 : 0.96
      transformOrigin: Item.Center
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { root.handleKey(event) }

      readonly property real heroWidth: Math.round(width * 0.36)
      readonly property real gap: Style.space(48)

      // ---- header ---------------------------------------------------------

      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(28)

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.lg

          Image {
            anchors.verticalCenter: parent.verticalCenter
            source: Qt.resolvedUrl("assets/duo.png")
            width: Style.space(22)
            height: Style.space(22)
            fillMode: Image.PreserveAspectFit
            smooth: true
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "DUOLINGO"
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            font.letterSpacing: 2
            textFormat: Text.PlainText
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.dateLine.toUpperCase()
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
            textFormat: Text.PlainText
          }
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Repeater {
            model: [["today", "Today"], ["history", "History"], ["help", "Help"]]
            delegate: Rectangle {
              required property var modelData
              readonly property bool current: root.pane === modelData[0]
              width: tabRow.implicitWidth + Style.spacing.controlPaddingX * 2
              height: Style.spacing.controlHeight
              radius: Style.cornerRadius
              color: current ? Util.alpha(root.duoGreen, 0.2) : tabMouse.containsMouse ? root.fill : "transparent"
              border.width: 1
              border.color: current ? Util.alpha(root.duoGreen, 0.6) : "transparent"
              Behavior on color { enabled: root.animated; ColorAnimation { duration: root.motionFast } }
              Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: Style.spacing.sm
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData[1]
                  color: current ? root.ink : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: current
                  textFormat: Text.PlainText
                }
              }
              MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.pane = modelData[0] }
            }
          }
        }
      }

      // ---- hero -------------------------------------------------------------

      Item {
        id: heroPane
        anchors.top: header.bottom
        anchors.topMargin: Style.space(20)
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: content.heroWidth

        // Subtle mascot feather — very low opacity, not kitsch
        Image {
          anchors.centerIn: dial
          width: dial.diameter * 0.42
          height: width
          source: Qt.resolvedUrl("assets/duo.svg")
          fillMode: Image.PreserveAspectFit
          opacity: 0.06
          smooth: true
          visible: status === Image.Ready
        }

        Dial {
          id: dial
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: -Style.space(44)
          anchors.horizontalCenter: parent.horizontalCenter
          diameter: Math.round(Math.min(parent.width, parent.height * 0.68, Style.space(400)))
          fraction: root.fraction
          water: root.water
          full: root.goalMet
        }

        Rectangle {
          anchors.centerIn: heroBadge
          width: heroBadge.height * 1.08
          height: width
          radius: width / 2
          color: Util.alpha(root.duoDone, 0.12)
          opacity: root.goalMet ? 1 : 0
          visible: opacity > 0.01
          Behavior on opacity { enabled: root.animated; NumberAnimation { duration: root.motionSlow; easing.type: Easing.OutCubic } }
        }

        // Large streak hero number + progress — honest, not a metric template
        Item {
          id: heroBadge
          anchors.horizontalCenter: dial.horizontalCenter
          anchors.verticalCenter: dial.verticalCenter
          anchors.verticalCenterOffset: -Math.round(dial.diameter * 0.04)
          width: dial.diameter * 0.56
          height: dial.diameter * 0.42

          Column {
            anchors.centerIn: parent
            spacing: 2
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.ready ? String(root.streak) : "--"
              color: root.heroText
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge * 1.25
              font.bold: true
              font.features: ({ "tnum": 1 })
              textFormat: Text.PlainText
              Behavior on color { enabled: root.animated; ColorAnimation { duration: root.motionSlow } }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "day streak"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: 1.2
              textFormat: Text.PlainText
            }
          }
        }

        Column {
          anchors.horizontalCenter: dial.horizontalCenter
          anchors.bottom: dial.bottom
          anchors.bottomMargin: -Style.space(8)
          spacing: 2
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(dial.frac * 100) + "%"
            color: root.heroText
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.features: ({ "tnum": 1 })
            textFormat: Text.PlainText
            Behavior on color { enabled: root.animated; ColorAnimation { duration: root.motionSlow } }
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.xpToday + " / " + root.goalXp + " XP today"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.features: ({ "tnum": 1 })
            textFormat: Text.PlainText
          }
        }

        Column {
          anchors.top: dial.bottom
          anchors.topMargin: Style.space(30)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.sm

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.headline.toUpperCase()
            color: root.heroText
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 1.5
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
            Behavior on color { enabled: root.animated; ColorAnimation { duration: root.motionSlow } }
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.statusLine
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            width: heroPane.width - Style.space(16)
          }
        }

        // Week strip below hero
        Column {
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width
          spacing: Style.space(6)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "THIS WEEK"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }

          Row {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: root.weekData
              delegate: Item {
                required property var modelData
                width: (parent.width - 6 * Style.space(4)) / 7
                height: Style.space(48)
                Column {
                  anchors.fill: parent
                  spacing: Style.space(4)
                  Rectangle {
                    width: parent.width
                    height: Style.space(28)
                    radius: Math.min(Style.cornerRadius, 4)
                    color: modelData.today ? Util.alpha(ink, 0.08) : Util.alpha(ink, 0.04)
                    border.width: modelData.today ? 1 : 0
                    border.color: modelData.today ? Util.alpha(ink, 0.12) : "transparent"
                    Rectangle {
                      anchors.bottom: parent.bottom
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.margins: 2
                      height: {
                        if (!modelData.hasData || modelData.xpEarned <= 0) return 2
                        var maxXp = root.goalXp
                        for (var i = 0; i < root.weekData.length; i++) if (root.weekData[i].xpEarned > maxXp) maxXp = root.weekData[i].xpEarned
                        var f = Math.max(0, Math.min(1, modelData.xpEarned / maxXp))
                        return Math.max(2, (parent.height - 4) * f)
                      }
                      radius: 2
                      color: modelData.today ? (root.goalMet ? root.duoGreen : Util.alpha(root.duoGreen, 0.9)) : Util.alpha(ink, 0.18)
                      Behavior on height { enabled: root.animated; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    }
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.letter
                    color: modelData.today ? root.ink : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: modelData.today
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.hasData && modelData.xpEarned > 0 ? String(modelData.xpEarned) : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: 9
                  }
                }
              }
            }
          }
        }
      }

      // ---- command line + panes ---------------------------------------------

      Item {
        id: rightPane
        anchors.top: header.bottom
        anchors.topMargin: Style.space(20)
        anchors.bottom: parent.bottom
        anchors.left: heroPane.right
        anchors.leftMargin: content.gap
        anchors.right: parent.right

        Rectangle {
          id: cmdBox
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width
          height: Style.space(56)
          radius: Math.min(Style.cornerRadius, Style.space(10))
          color: root.fill
          border.width: cmd.activeFocus ? 2 : 1
          border.color: cmd.activeFocus ? Util.alpha(root.duoGreen, 0.7) : root.hairline
          Behavior on border.color { enabled: root.animated; ColorAnimation { duration: root.motionFast } }

          Text {
            id: prompt
            anchors.left: parent.left
            anchors.leftMargin: Style.space(18)
            anchors.verticalCenter: parent.verticalCenter
            text: ">"
            color: cmd.text.length ? root.duoGreen : root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconLarge
            textFormat: Text.PlainText
            Behavior on color { enabled: root.animated; ColorAnimation { duration: root.motionFast } }
          }

          Item {
            anchors.left: prompt.right
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(18)
            anchors.verticalCenter: parent.verticalCenter
            height: cmd.implicitHeight
            clip: true

            TextInput {
              id: cmd
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(1, Math.ceil(contentWidth) + 2)
              color: root.ink
              selectionColor: Util.alpha(root.duoGreen, 0.35)
              selectedTextColor: root.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              selectByMouse: true
              cursorVisible: true
            }

            Text {
              anchors.left: cmd.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.ghost
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              textFormat: Text.PlainText
            }

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              visible: !cmd.text.length
              text: "practice, refresh, username <name>, goal 100, help"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              textFormat: Text.PlainText
              elide: Text.ElideRight
              width: parent.width
            }
          }

          MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: cmd.forceActiveFocus(); z: -1 }
        }

        // Preview / toast row
        Item {
          id: previewRow
          anchors.top: cmdBox.bottom
          anchors.topMargin: Style.spacing.md
          width: parent.width
          height: Style.space(22)
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: root.toast !== "" ? root.toast : root.livePreview ? (root.livePreview.ok ? root.livePreview.preview : root.livePreview.error) : ""
            color: root.toast !== "" ? (root.toastError ? root.urgent : root.heroText) : root.livePreview && !root.livePreview.ok ? root.faint : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: root.toast !== ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            width: parent.width - Style.space(8)
            opacity: text.length ? 1 : 0
            Behavior on opacity { enabled: root.animated; NumberAnimation { duration: root.motionFast } }
          }
        }

        // Suggestions
        Column {
          id: suggestionList
          anchors.top: previewRow.bottom
          anchors.topMargin: Style.spacing.sm
          width: parent.width
          spacing: Style.spacing.xxs
          visible: cmd.text.length > 0 || root.pane === "today"

          Repeater {
            model: root.suggestions
            delegate: Item {
              id: sRow
              required property var modelData
              required property int index
              readonly property bool current: index === root.selected && cmd.text.length > 0
              width: parent.width
              height: Style.space(30)
              Rectangle {
                anchors.fill: parent
                radius: Math.min(Style.cornerRadius, Style.space(6))
                color: sRow.current ? Util.alpha(root.duoGreen, 0.14) : sMouse.containsMouse ? root.fill : "transparent"
                Behavior on color { enabled: root.animated; ColorAnimation { duration: root.motionFast } }
              }
              Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(3); height: parent.height * 0.6
                radius: width / 2
                color: root.duoGreen
                opacity: sRow.current ? 1 : 0
                Behavior on opacity { enabled: root.animated; NumberAnimation { duration: root.motionFast } }
              }
              Text {
                id: sName
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                text: sRow.modelData.name + (sRow.modelData.arg ? " " + sRow.modelData.arg : "")
                color: sRow.current ? root.ink : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: sRow.current
                textFormat: Text.PlainText
              }
              Text {
                anchors.left: sName.right
                anchors.leftMargin: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                text: sRow.modelData.hint
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                textFormat: Text.PlainText
                elide: Text.ElideRight
              }
              MouseArea {
                id: sMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { root.selected = sRow.index; if (sRow.modelData.arg) root.accept(); else { cmd.text = sRow.modelData.completion; root.submit() } }
              }
            }
          }
        }

        // ---- panes --------------------------------------------------------

        Item {
          id: panes
          anchors.top: suggestionList.visible ? suggestionList.bottom : previewRow.bottom
          anchors.topMargin: Style.space(20)
          anchors.bottom: parent.bottom
          width: parent.width
          clip: true

          // today ------------------------------------------------------------
          Item {
            anchors.fill: parent
            visible: root.pane === "today"

            Column {
              width: parent.width
              spacing: Style.spacing.md

              // Goal progress
              Column {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: "TODAY"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }
                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    text: root.xpToday + " / " + root.goalXp + " XP"
                    color: root.goalMet ? root.duoGreen : root.ink
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    text: root.goalMet ? "— goal met" : "— " + Math.max(0, root.goalXp - root.xpToday) + " XP to go"
                    color: root.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
                Rectangle {
                  width: parent.width
                  height: 4
                  radius: 2
                  color: Util.alpha(ink, 0.08)
                  Rectangle {
                    height: parent.height
                    width: parent.width * Math.max(0, Math.min(1, root.fraction))
                    radius: parent.radius
                    color: root.goalMet ? root.duoGreen : Util.alpha(root.duoGreen, 0.9)
                    Behavior on width { enabled: root.animated; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                  }
                }
              }

              // Streak card
              Rectangle {
                width: parent.width
                implicitHeight: streakCol.implicitHeight + Style.space(16)
                radius: Math.min(Style.cornerRadius, 8)
                color: Util.alpha(ink, 0.05)
                border.width: 1
                border.color: Util.alpha(ink, 0.08)
                Column {
                  id: streakCol
                  x: Style.space(12)
                  y: Style.space(12)
                  width: parent.width - Style.space(24)
                  spacing: Style.space(4)
                  Text {
                    text: "Streak"
                    color: root.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.2
                  }
                  Text {
                    text: root.ready ? String(root.streak) + " days" + (root.streakExtendedToday ? " — done today" : " — pending") : "No data yet"
                    color: root.ink
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }
                  Text {
                    text: root.ready && root.userData ? "@" + root.userData.username + " · " + Model.formatNumber(root.userData.totalXp) + " XP total" : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    visible: text.length > 0
                  }
                }
              }

              // Courses if available
              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: root.userData && root.userData.courses && root.userData.courses.length > 0
                Text {
                  text: "COURSES"
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }
                Repeater {
                  model: root.userData && root.userData.courses ? root.userData.courses.slice(0, 4) : []
                  delegate: Item {
                    required property var modelData
                    width: parent.width
                    height: Style.space(28)
                    Rectangle {
                      anchors.fill: parent
                      radius: Math.min(Style.cornerRadius, 6)
                      color: Util.alpha(ink, 0.04)
                    }
                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      spacing: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      Text { text: modelData.flag; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
                      Text { text: modelData.title; color: root.ink; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter; width: parent.width - Style.space(120); elide: Text.ElideRight }
                      Text { text: Model.formatNumber(modelData.xp) + " XP"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                    }
                  }
                }
              }

              Text {
                width: parent.width
                text: "PgUp/PgDn switches panes  ·  Tab completes  ·  Enter runs  ·  Esc clears, then closes"
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          // history ----------------------------------------------------------
          Item {
            anchors.fill: parent
            visible: root.pane === "history"

            Column {
              width: parent.width
              spacing: Style.spacing.sm

              Row {
                width: parent.width
                Text { text: "Past days"; color: root.ink; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true }
                Text { text: root.pastDays.length ? "(" + root.pastDays.length + " days)" : ""; color: root.faint; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
              }

              ListView {
                width: parent.width
                height: Math.max(0, panes.height - y)
                clip: true
                spacing: Style.spacing.xxs
                model: root.pastDays
                delegate: Item {
                  required property var modelData
                  width: ListView.view.width
                  height: Style.space(30)
                  Text {
                    id: dayLabel
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(90)
                    text: modelData.label
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Rectangle {
                    id: track
                    anchors.left: dayLabel.right
                    anchors.right: dayAmount.left
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    height: Style.space(6)
                    radius: height / 2
                    color: root.fill
                    Rectangle {
                      width: parent.width * Math.min(1, modelData.fraction)
                      height: parent.height
                      radius: height / 2
                      color: modelData.xpEarned >= root.goalXp ? root.duoGreen : Util.alpha(root.duoGreen, 0.6)
                    }
                  }
                  Text {
                    id: dayAmount
                    anchors.right: dayMark.left
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.xpEarned > 0 ? "+" + modelData.xpEarned + " XP" : "0 XP"
                    color: modelData.xpEarned > 0 ? root.ink : root.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    font.features: ({ "tnum": 1 })
                  }
                  Text {
                    id: dayMark
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(16)
                    text: modelData.xpEarned >= root.goalXp ? "ok" : ""
                    color: root.duoGreen
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
                Text {
                  anchors.centerIn: parent
                  visible: root.pastDays.length === 0
                  text: "No history yet — your first day of tracking starts now"
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          // help -------------------------------------------------------------
          Column {
            anchors.fill: parent
            visible: root.pane === "help"
            spacing: Style.spacing.sm

            Text {
              width: parent.width
              text: "Commands  —  Tab completes  ·  Enter runs  ·  Esc clears, then closes  ·  PgUp/PgDn switches panes"
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: Commands.helpRows()
              delegate: Item {
                required property var modelData
                width: parent.width
                height: Style.space(28)
                Text {
                  id: helpName
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(170)
                  text: modelData.name
                  color: root.ink
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  id: helpAlias
                  anchors.left: helpName.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(140)
                  text: modelData.aliases
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
                Text {
                  anchors.left: helpAlias.right
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.hint
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- dial component

  component Dial: Item {
    id: dial
    property real fraction: 0
    property color water: root.duoGreen
    property bool full: false
    property real diameter: Style.space(360)
    readonly property real dialStart: 135
    readonly property real dialSweep: 270
    readonly property int tickCount: 36
    readonly property real arcWidth: Style.space(5)
    readonly property real arcRadius: diameter / 2 - arcWidth
    readonly property color trackColor: Util.alpha(ink, 0.12)
    readonly property color minorTickColor: Util.alpha(ink, 0.10)
    readonly property color majorTickColor: Util.alpha(ink, 0.24)

    property real shown: 0
    readonly property real frac: Math.max(0, Math.min(1, shown))
    readonly property bool arcVisible: frac > 0.004

    width: diameter
    height: diameter

    Behavior on shown {
      enabled: root.animated && !ignition.running
      NumberAnimation { duration: root.motionSlow * 2; easing.type: Easing.OutCubic }
    }
    onFractionChanged: if (!ignition.running) shown = fraction
    Component.onCompleted: shown = fraction

    function ignite() {
      if (!root.animated) { shown = fraction; return }
      ignition.restart()
    }

    SequentialAnimation {
      id: ignition
      NumberAnimation { target: dial; property: "shown"; to: 1; duration: 520; easing.type: Easing.InOutCubic }
      NumberAnimation { target: dial; property: "shown"; to: dial.fraction; duration: 620; easing.type: Easing.OutCubic }
      onFinished: dial.shown = dial.fraction
    }

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeWidth: dial.arcWidth
        strokeColor: dial.trackColor
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        PathAngleArc {
          centerX: dial.width / 2; centerY: dial.height / 2
          radiusX: dial.arcRadius; radiusY: dial.arcRadius
          startAngle: dial.dialStart; sweepAngle: dial.dialSweep
        }
      }

      ShapePath {
        strokeWidth: dial.arcWidth * 3
        strokeColor: dial.arcVisible ? Util.alpha(dial.water, dial.full ? 0.28 : 0.18) : "transparent"
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        PathAngleArc {
          centerX: dial.width / 2; centerY: dial.height / 2
          radiusX: dial.arcRadius; radiusY: dial.arcRadius
          startAngle: dial.dialStart; sweepAngle: dial.dialSweep * dial.frac
        }
      }

      ShapePath {
        strokeWidth: dial.arcWidth
        strokeColor: dial.arcVisible ? dial.water : "transparent"
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        PathAngleArc {
          centerX: dial.width / 2; centerY: dial.height / 2
          radiusX: dial.arcRadius; radiusY: dial.arcRadius
          startAngle: dial.dialStart; sweepAngle: dial.dialSweep * dial.frac
        }
      }
    }

    Repeater {
      model: dial.tickCount
      Item {
        required property int index
        readonly property bool major: index % 4 === 0
        readonly property bool lit: dial.frac > 0.004 && index / (dial.tickCount - 1) <= dial.frac
        anchors.fill: parent
        rotation: dial.dialStart + (index / (dial.tickCount - 1)) * dial.dialSweep - 270
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          y: dial.arcWidth * 2 + (parent.major ? 0 : Style.space(2))
          width: parent.major ? Math.max(2, Style.space(2)) : 1
          height: parent.major ? Style.space(9) : Style.space(5)
          radius: width / 2
          color: parent.lit ? Util.alpha(dial.water, parent.major ? 1 : 0.6) : parent.major ? dial.majorTickColor : dial.minorTickColor
        }
      }
    }
  }
}
