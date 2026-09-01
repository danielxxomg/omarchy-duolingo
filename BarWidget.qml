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

  property string resolvedUsername: ""
  property var userData: null
  property bool fetching: false
  property string lastError: ""

  function effectiveUsername() {
    return (configuredUsername || resolvedUsername || "").trim()
  }

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
    var user = root.effectiveUsername()
    if (user === "") {
      if (!detectProc.running) detectProc.running = true
      return
    }
    if (fetchProc.running) return
    root.fetching = true
    fetchProc.command = ["curl", "-fsS", "--max-time", "6", "https://www.duolingo.com/2017-06-30/users?username=" + encodeURIComponent(user)]
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
    id: detectProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/user.duolingo/bin/detect-user.py"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var detected = String(text || "").trim()
        if (detected !== "") {
          root.resolvedUsername = detected
          root.refresh()
        } else {
          root.userData = { valid: false, error: "Set username in panel" }
        }
      }
    }
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
    text: Model.barText(root.userData, root.showXp)
    tooltipText: Model.tooltipText(root.userData)
    labelVisible: true
    hasVisualContent: true
    horizontalMargin: 8.5
    verticalPadding: 6

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (root.bar) {
          root.bar.run("which duolingo-desktop >/dev/null 2>&1 && setsid duolingo-desktop || omarchy-launch-webapp https://www.duolingo.com")
        }
      } else if (mouseButton === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.togglePanel()
      }
    }
  }
}
