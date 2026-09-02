import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "user.duolingo"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property bool showXp: setting("showXp", false) === true
  readonly property bool reducedMotion: setting("reducedMotion", false) === true

  readonly property color accentColor: Color.accent || "#58cc02"
  readonly property color urgent: bar ? bar.urgent : Color.urgent

  readonly property var userData: service ? service.userData : null
  readonly property bool fetching: service ? service.fetching === true : false
  readonly property string lastError: service ? service.lastError : ""
  readonly property int xpToday: service ? service.xpToday : 0
  readonly property int goalXp: service ? service.goalXp : 50

  Connections {
    target: root.service
    function onRequestPanelToggle() { root.togglePanel() }
    function onRequestPanelOpen() { root.open() }
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("userData" in target) target.userData = root.userData
    if ("service" in target) target.service = root.service
    if (root.service && "widgetSettings" in root.service)
      root.service.widgetSettings = root.settings
  }

  function refresh() {
    if (root.service && typeof root.service.refresh === "function") root.service.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property real openPanelIndicatorWidth: barRow.implicitWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()
  onUserDataChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Math.round(barRow.implicitWidth + Style.spaceReal(8.5) * 2)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    tooltipText: {
      var base = Model.tooltipText(root.userData)
      if (root.service && root.userData && root.userData.valid) {
        base += " · " + root.xpToday + " / " + root.goalXp + " XP today"
        if (root.service.goalMet) base += " — goal met"
      }
      base += " · Right click launches Duolingo, overlay via omarchy-shell user.duolingo overlay"
      return base
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (root.service && typeof root.service.launchDuolingo === "function") root.service.launchDuolingo()
        else if (root.bar) root.bar.run(root.pluginDir + "/bin/launch-duo.sh")
      } else if (mouseButton === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.togglePanel()
      }
    }

    Row {
      id: barRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      // Duo icon (pulses while fetching).
      Item {
        width: Style.space(16)
        height: Style.space(16)
        implicitWidth: Style.space(16)
        implicitHeight: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter

        Image {
          source: Qt.resolvedUrl("assets/duo.png")
          anchors.fill: parent
          fillMode: Image.PreserveAspectFit
          smooth: true
          opacity: root.fetching ? 0.45 : 1.0
          Behavior on opacity { NumberAnimation { duration: 220 } }
        }
      }

      // Streak number on a state pill: the pill's color carries the daily
      // goal state at a glance (gray no-data, green fills with progress,
      // solid green when met, pulsing red when the day is almost over and
      // the streak is still pending).
      //
      // Pill states:
      //   noData      gray  (0.10) — no data or not configured
      //   atRisk      urgent red, pulsing — goal unmet and < 3h to midnight
      //   goalMet     green solid (1.0) with soft glow
      //   inProgress  green tinted by progress fraction (0.14..0.55)
      readonly property bool hasData: root.userData && root.userData.valid
      readonly property bool streakDone: hasData && root.userData.streakExtendedToday === true
      readonly property int hoursToMidnight: (24 - new Date().getHours()) % 24
      readonly property bool atRisk: hasData && !streakDone && root.hoursToMidnight < 3
      readonly property real goalFrac: hasData && root.goalXp > 0
                                       ? Math.max(0, Math.min(1, root.xpToday / root.goalXp)) : 0
      // Urgency ramps up as midnight approaches during the final 6 hours.
      readonly property real urgency: hasData && !streakDone
                                      ? Math.max(0, Math.min(1, (6 - root.hoursToMidnight) / 6)) : 0

      Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: streakLabel.implicitWidth + Style.space(12)
        implicitHeight: streakLabel.implicitHeight + Style.space(5)
        radius: height / 2

        readonly property color pillGreen: root.accentColor
        readonly property color pillUrgent: root.urgent

        color: {
          if (!barRow.hasData) return Qt.rgba(0.5, 0.5, 0.5, 0.10)
          if (barRow.streakDone) return Qt.rgba(pillGreen.r, pillGreen.g, pillGreen.b, 0.9)
          if (barRow.atRisk) return Qt.rgba(pillUrgent.r, pillUrgent.g, pillUrgent.b, 0.9)
          // Blend from transparent toward green as XP accumulates.
          var a = 0.14 + 0.41 * barRow.goalFrac
          var c = Qt.rgba(pillGreen.r, pillGreen.g, pillGreen.b, a)
          // Warn earlier than at-risk: tint red as the day runs out.
          return barRow.urgency > 0 ? Qt.tint(c, Qt.rgba(pillUrgent.r, pillUrgent.g, pillUrgent.b, 0.45 * barRow.urgency)) : c
        }

        SequentialAnimation on opacity {
          running: barRow.atRisk && !root.reducedMotion
          loops: Animation.Infinite
          NumberAnimation { from: 1.0; to: 0.55; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.55; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
        }

        Behavior on color {
          enabled: !root.reducedMotion
          ColorAnimation { duration: 320 }
        }

        Rectangle {
          anchors.fill: parent
          radius: parent.radius
          visible: barRow.streakDone && !root.reducedMotion
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(pill.pillGreen.r, pill.pillGreen.g, pill.pillGreen.b, 0.55)
        }

        Text {
          id: streakLabel
          anchors.centerIn: parent
          text: {
            if (!barRow.hasData) return "Duo"
            if (root.showXp) return Model.formatNumber(root.userData.totalXp) + " XP"
            return String(root.userData.streak)
          }
          color: {
            if (!barRow.hasData) return root.bar ? root.bar.foreground : Color.foreground
            if (barRow.streakDone || barRow.atRisk) return "#ffffff"
            return root.bar ? root.bar.foreground : Color.foreground
          }
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }
    }
  }
}
