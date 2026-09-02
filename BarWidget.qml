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

      // Duo icon wrapped in a daily-goal progress ring.
      Item {
        id: ringItem
        width: Style.space(16)
        height: Style.space(16)
        implicitWidth: Style.space(16)
        implicitHeight: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter

        readonly property real frac: {
          if (!root.userData || !root.userData.valid || root.goalXp <= 0) return 0
          return Math.max(0, Math.min(1, root.xpToday / root.goalXp))
        }
        readonly property bool hasData: root.userData && root.userData.valid
        readonly property color ringColor: hasData ? root.accentColor : "transparent"

        Shape {
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          visible: ringItem.hasData
          layer.enabled: true
          layer.samples: 4

          // Track
          ShapePath {
            strokeWidth: 1.5
            strokeColor: root.userData && root.userData.streakExtendedToday
                         ? Qt.rgba(root.ringItem.ringColor.r, root.ringItem.ringColor.g, root.ringItem.ringColor.b, 0.25)
                         : Qt.rgba(0.5, 0.5, 0.5, 0.35)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
              centerX: ringItem.width / 2; centerY: ringItem.height / 2
              radiusX: ringItem.width / 2 - 1; radiusY: ringItem.height / 2 - 1
              startAngle: -90; sweepAngle: 360
            }
          }

          // Progress arc: fills clockwise from 12 o'clock as XP accumulates
          ShapePath {
            strokeWidth: 1.5
            strokeColor: ringItem.ringColor
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
              centerX: ringItem.width / 2; centerY: ringItem.height / 2
              radiusX: ringItem.width / 2 - 1; radiusY: ringItem.height / 2 - 1
              startAngle: -90; sweepAngle: 360 * ringItem.frac
            }
          }
        }

        Image {
          source: Qt.resolvedUrl("assets/duo.png")
          anchors.fill: parent
          anchors.margins: 2
          fillMode: Image.PreserveAspectFit
          smooth: true
          opacity: root.fetching ? 0.45 : 1.0
          Behavior on opacity { NumberAnimation { duration: 220 } }
        }
      }

      Text {
        id: streakLabel
        text: {
          if (!root.userData || !root.userData.valid) return "Duo"
          if (root.showXp) return Model.formatNumber(root.userData.totalXp) + " XP"
          return String(root.userData.streak)
        }
        color: {
          if (!root.userData || !root.userData.valid) return root.bar ? root.bar.foreground : Color.foreground
          if (root.userData.streakExtendedToday) return root.accentColor
          return root.urgent
        }
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
