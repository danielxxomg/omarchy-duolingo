import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "user.duolingo"

  readonly property string configuredUsername: setting("username", "")
  readonly property int refreshMinutes: Math.max(5, parseInt(setting("refreshMinutes", 15), 10) || 15)
  readonly property bool showXp: setting("showXp", false) === true

  readonly property color accentColor: Color.accent || "#58cc02"
  readonly property color urgent: bar ? bar.urgent : Color.urgent

  property var userData: null
  property bool fetching: false
  property string lastError: ""

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("userData" in target) target.userData = root.userData
  }

  function refresh() {
    if (fetchProc.running) return
    root.fetching = true
    var user = (root.configuredUsername || "").trim()
    if (user !== "") {
      fetchProc.command = [Quickshell.env("HOME") + "/.config/omarchy/plugins/user.duolingo/bin/fetch-duo.py", user]
    } else {
      fetchProc.command = [Quickshell.env("HOME") + "/.config/omarchy/plugins/user.duolingo/bin/fetch-duo.py"]
    }
    fetchProc.running = true
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

  readonly property real openPanelIndicatorWidth: button.labelWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    refresh()
  }
  onUserDataChanged: injectPanel()

  Component.onCompleted: {
    refresh()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.fetching = false
        var raw = String(text || "").trim()
        if (!raw) {
          root.lastError = "Network error or user not found"
          return
        }
        var data = Model.parseUserData(raw)
        root.userData = data
        if (!data.valid) {
          root.lastError = data.error
        } else {
          root.lastError = ""
        }
      }
    }
  }

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
    fixedWidth: root.vertical ? -1 : Math.round(barContent.implicitWidth + Style.spaceReal(8.5) * 2)
    tooltipText: Model.tooltipText(root.userData)

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (root.bar) {
          root.bar.run(Quickshell.env("HOME") + "/.config/omarchy/plugins/user.duolingo/bin/launch-duo.sh")
        }
      } else if (mouseButton === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.togglePanel()
      }
    }

    Row {
      id: barContent
      anchors.centerIn: parent
      spacing: Style.space(5)

      Image {
        source: Qt.resolvedUrl("assets/duo.png")
        width: Style.space(16)
        height: Style.space(16)
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: {
          if (!root.userData || !root.userData.valid) return "Duo"
          if (root.showXp) return Model.formatNumber(root.userData.totalXp) + " XP"
          return String(root.userData.streak)
        }
        color: {
          if (!root.userData || !root.userData.valid) return button.foreground
          if (root.userData.streakExtendedToday) return root.accentColor
          return root.urgent
        }
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
