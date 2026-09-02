import QtQuick
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
    tooltipText: Model.tooltipText(root.userData)

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
