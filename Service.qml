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

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string iconPath: pluginDir + "/assets/duo.png"

  property var userData: null
  property string lastError: ""
  property bool fetching: false
  property bool isStale: false
  property bool notifiedToday: false
  property string lastNotifiedDate: ""

  function refresh() {
    if (fetchProc.running) return
    root.fetching = true
    var user = (root.configuredUsername || "").trim()
    if (user !== "") {
      fetchProc.command = [root.pluginDir + "/bin/fetch-duo.py", user]
    } else {
      fetchProc.command = [root.pluginDir + "/bin/fetch-duo.py"]
    }
    fetchProc.running = true
  }

  function launchDuolingo() {
    launchProc.command = [root.pluginDir + "/bin/launch-duo.sh"]
    launchProc.running = true
  }

  function checkReminder() {
    if (!root.remindersEnabled || !root.userData || !root.userData.valid) return

    var todayStr = Model.dayKey(new Date())

    if (lastNotifiedDate !== todayStr) {
      notifiedToday = false
      lastNotifiedDate = todayStr
    }

    if (notifiedToday) return

    var now = new Date()
    if (now.getHours() >= root.remindHour && !root.userData.streakExtendedToday) {
      notifiedToday = true
      var title = "Duolingo streak reminder"
      var body = "You haven't completed your daily lesson today. Keep your " + root.userData.streak + "-day streak alive!"
      notifyProc.command = ["notify-send", "-a", "Duolingo", "-u", "normal", "-i", root.iconPath,
        "-h", "string:x-canonical-private-synchronous:duolingo", title, body]
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
        root.fetching = false
        var raw = String(text || "").trim()
        if (!raw) {
          root.lastError = "Network error or user not found"
          return
        }
        var data = Model.parseUserData(raw)
        if (data.valid) {
          root.userData = data
          root.lastError = ""
          root.isStale = false
          root.checkReminder()
        } else {
          // Keep previous valid data as stale if present
          if (root.userData && root.userData.valid) {
            root.isStale = true
          } else {
            root.userData = data
            root.isStale = false
          }
          root.lastError = data.error || "Failed to fetch Duolingo data"
        }
      }
    }
  }

  Process {
    id: notifyProc
  }

  Process {
    id: launchProc
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
