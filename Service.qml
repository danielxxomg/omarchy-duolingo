import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  property var widgetSettings: ({})

  function widgetSetting(name, fallback) {
    var value = widgetSettings ? widgetSettings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property string configuredUsername: String(widgetSetting("username", ""))
  readonly property int refreshMinutes: Math.max(5, parseInt(widgetSetting("refreshMinutes", 15), 10) || 15)
  readonly property bool remindersEnabled: widgetSetting("remindersEnabled", true) !== false
  readonly property int remindHour: Util.clamp(parseInt(widgetSetting("remindHour", 20), 10) || 20, 0, 23)

  property var userData: null
  property bool notifiedToday: false
  property string lastNotifiedDate: ""

  function refresh() {
    if (fetchProc.running) return
    var user = (root.configuredUsername || "").trim()
    if (user !== "") {
      fetchProc.command = [Quickshell.env("HOME") + "/.config/omarchy/plugins/user.duolingo/bin/fetch-duo.py", user]
    } else {
      fetchProc.command = [Quickshell.env("HOME") + "/.config/omarchy/plugins/user.duolingo/bin/fetch-duo.py"]
    }
    fetchProc.running = true
  }

  function launchDuolingo() {
    notifyProc.command = ["bash", "-c", "which duolingo-desktop >/dev/null 2>&1 && setsid duolingo-desktop || omarchy-launch-webapp https://www.duolingo.com"]
    notifyProc.running = true
  }

  function checkReminder() {
    if (!root.remindersEnabled || !root.userData || !root.userData.valid) return
    
    var now = new Date()
    var todayStr = now.getFullYear() + "-" + (now.getMonth() + 1) + "-" + now.getDate()
    
    if (lastNotifiedDate !== todayStr) {
      notifiedToday = false
      lastNotifiedDate = todayStr
    }

    if (notifiedToday) return

    if (now.getHours() >= root.remindHour && !root.userData.streakExtendedToday) {
      notifiedToday = true
      var title = "Duolingo: Streak in danger! 🔥"
      var body = "You haven't completed your daily lesson today. Keep your " + root.userData.streak + "-day streak alive!"
      notifyProc.command = ["notify-send", "-a", "Duolingo", "-i", "dialog-warning", title, body]
      notifyProc.running = true
    }
  }

  Component.onCompleted: {
    refresh()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    onTriggered: {
      root.refresh()
      root.checkReminder()
    }
  }

  Timer {
    id: reminderTick
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.checkReminder()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        var data = Model.parseUserData(raw)
        if (data.valid) {
          root.userData = data
          root.checkReminder()
        }
      }
    }
  }

  Process {
    id: notifyProc
  }

  IpcHandler {
    target: "duolingo"

    function status(): string {
      return Model.statusSummary(root.userData)
    }

    function refresh(): string {
      root.refresh()
      return "Refreshing Duolingo stats…"
    }

    function launch(): string {
      root.launchDuolingo()
      return "Launching Duolingo…"
    }

    function streak(): string {
      return root.userData && root.userData.valid ? String(root.userData.streak) : "0"
    }
  }
}
