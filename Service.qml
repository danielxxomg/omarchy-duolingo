import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model
import "Commands.js" as Commands

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
  readonly property bool autoDetect: widgetSetting("autoDetect", true) !== false
  readonly property int refreshMinutes: Math.max(5, parseInt(widgetSetting("refreshMinutes", 15), 10) || 15)
  readonly property bool remindersEnabled: widgetSetting("remindersEnabled", true) !== false
  readonly property int remindHour: Util.clamp(parseInt(widgetSetting("remindHour", 20), 10) || 20, 0, 23)
  readonly property int goalXp: Util.clamp(Math.round(Number(widgetSetting("goalXp", 50))) || 50, 10, 1000)
  readonly property bool reducedMotion: widgetSetting("reducedMotion", false) === true
  readonly property bool showXp: widgetSetting("showXp", false) === true

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string iconPath: pluginDir + "/assets/duo.png"

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/duolingo"
  readonly property string stateFilePath: stateDir + "/history.json"
  readonly property int maxStateBytes: 262144

  property var userData: null
  property string lastError: ""
  property bool fetching: false
  property bool isStale: false
  property bool notifiedToday: false
  property string lastNotifiedDate: ""
  property string lastCatchUpDate: ""

  property var history: Model.emptyHistory()
  property bool historyLoaded: false
  property bool saveQueued: false
  property int diskRev: 0
  property int writingRev: 0
  property bool dead: false

  readonly property int xpToday: Model.xpToday(root.userData, root.history)
  readonly property var weekHistory: Model.weekHistory(root.history)
  readonly property real goalFraction: Model.fraction(root.xpToday, root.goalXp)
  readonly property bool goalMet: root.xpToday >= root.goalXp

  onWidgetSettingsChanged: {
    // Timer interval binding is declarative but may not restart; update explicitly
    refreshTimer.interval = root.refreshMinutes * 60 * 1000
  }

  function refresh() {
    if (fetchProc.running) return
    root.fetching = true
    var user = (root.configuredUsername || "").trim()
    if (user !== "") {
      fetchProc.command = [root.pluginDir + "/bin/fetch-duo.py", user]
    } else if (!root.autoDetect) {
      fetchProc.command = [root.pluginDir + "/bin/fetch-duo.py", "--no-detect"]
    } else {
      fetchProc.command = [root.pluginDir + "/bin/fetch-duo.py"]
    }
    fetchProc.running = true
  }

  function launchDuolingo() {
    launchProc.command = [root.pluginDir + "/bin/launch-duo.sh"]
    launchProc.running = true
  }

  // ---------------------------------------------------------------- settings IPC

  function setSettings(values) {
    var entry = { id: "user.duolingo" }
    for (var k in root.widgetSettings) if (k !== "id") entry[k] = root.widgetSettings[k]
    for (var key in values) {
      if (values[key] === undefined) delete entry[key]
      else entry[key] = values[key]
    }
    if (entry.username !== undefined) entry.username = String(entry.username).trim()
    root.widgetSettings = entry
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline("user.duolingo", entry)
    if (values.username !== undefined) root.refresh()
  }

  function setSetting(key, value) { var v = {}; v[key] = value; setSettings(v) }

  function setUsername(name) {
    var w = String(name || "").trim()
    if (!/^[A-Za-z0-9_.-]{2,25}$/.test(w)) return
    setSetting("username", w)
  }

  function persistUsername(name) { setUsername(name) }

  function setGoal(n) {
    var v = Util.clamp(Math.round(Number(n)) || 50, 10, 1000)
    setSetting("goalXp", v)
  }

  signal requestPanelToggle()
  signal requestPanelOpen()
  signal requestOverlayClose()

  function runCommand(text) {
    var parsed = Commands.parse(text, Commands.contextOf(root))
    if (!parsed.ok) return parsed.error || "Nothing to do"
    if (parsed.ui === "close") { root.requestOverlayClose(); return parsed.preview }
    if (parsed.ui === "open") { root.requestPanelOpen(); return parsed.preview }
    if (parsed.ui) return parsed.preview
    return Commands.execute(root, parsed)
  }

  function openOverlay() {
    if (root.shell && typeof root.shell.toggle === "function") root.shell.toggle("user.duolingo", "{}")
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

  // Offline catch-up: PC off at remindHour + failed fetch should still warn once, using last known history state.
  function checkOfflineCatchUp() {
    if (!root.remindersEnabled) return
    if (!root.historyLoaded) return
    if (root.userData && root.userData.valid) return
    var hasFailure = root.lastError !== "" || (root.userData && !root.userData.valid)
    if (!hasFailure) return
    var todayKey = Model.dayKey(new Date())
    if (root.lastCatchUpDate === todayKey) return
    if (root.lastNotifiedDate !== todayKey) {
      root.notifiedToday = false
      root.lastNotifiedDate = todayKey
    }
    if (root.notifiedToday) return
    var now = new Date()
    if (now.getHours() < root.remindHour) return
    var entry = root.history && root.history.days ? root.history.days[todayKey] : null
    if (entry && entry.streakExtendedToday === true) return
    root.lastCatchUpDate = todayKey
    root.notifiedToday = true
    root.lastNotifiedDate = todayKey
    var title = "Duolingo streak pending — offline"
    var body = "Your streak may be at risk. Complete a lesson soon to keep your streak alive."
    notifyProc.command = ["notify-send", "-a", "Duolingo", "-u", "normal", "-i", root.iconPath,
      "-h", "string:x-canonical-private-synchronous:duolingo", title, body]
    notifyProc.running = true
  }

  function updateHistory(data) {
    if (!data || !data.valid) return
    var todayKey = Model.dayKey(new Date())
    var h = root.history
    if (!h || !h.days) h = Model.emptyHistory()
    // Deep copy days to avoid mutating binding directly
    var days = {}
    for (var k in h.days) days[k] = h.days[k]
    var coursesMap = {}
    if (data.courses && data.courses.length) {
      for (var i = 0; i < data.courses.length; i++) {
        var c = data.courses[i]
        var lang = c.learningLanguage || c.title || String(i)
        coursesMap[lang] = { xp: c.xp || 0, crowns: c.crowns || 0 }
      }
    }
    var existing = days[todayKey]
    if (!existing) {
      days[todayKey] = { streak: data.streak, totalXp: data.totalXp, firstTotalXp: data.totalXp, courses: coursesMap, streakExtendedToday: data.streakExtendedToday === true }
    } else {
      var first = existing.firstTotalXp !== undefined ? existing.firstTotalXp : existing.totalXp
      days[todayKey] = { streak: data.streak, totalXp: data.totalXp, firstTotalXp: first, courses: coursesMap, streakExtendedToday: data.streakExtendedToday === true }
    }
    days = Model.pruneHistory(days, todayKey)
    var next = { rev: h.rev || 0, days: days, updatedAt: new Date().toISOString() }
    root.history = JSON.parse(JSON.stringify(next))
    saveHistory()
  }

  Component.onCompleted: {
    loadHistory()
    refresh()
  }
  Component.onDestruction: root.dead = true

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
          root.updateHistory(data)
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

  // ---------------------------------------------------------------- persistence
  Process {
    id: historyReader
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = null
        try { parsed = text.trim() === "" ? null : JSON.parse(text) } catch (e) { parsed = null }
        root.diskRev = parsed && isFinite(Number(parsed.rev)) ? Math.max(0, Math.round(Number(parsed.rev))) : 0
        root.history = Model.normalizeHistory(parsed)
        root.historyLoaded = true
        if (root.saveQueued) { root.saveQueued = false; root.saveHistory() }
        root.checkOfflineCatchUp()
      }
    }
  }

  function loadHistory() {
    if (historyReader.running) return
    historyReader.command = ["bash", "-c",
      'f="$0"; [ -e "$f" ] || exit 0; [ -L "$f" ] && exit 1; exec 3<>"$f" || exit 1; '
      + '[ "$(stat -Lc %F /proc/self/fd/3)" = "regular file" ] || exit 1; '
      + 'head -c ' + root.maxStateBytes + ' <&3',
      root.stateFilePath]
    historyReader.running = true
  }

  Process {
    id: historyWriter
    running: false
    onExited: function(code, status) {
      if (code === 3) {
        root.loadHistory()
        return
      }
      if (code === 0) {
        root.diskRev = root.writingRev
      }
      if (root.saveQueued) { root.saveQueued = false; root.saveHistory() }
    }
  }

  function saveHistory() {
    if (!root.historyLoaded || root.dead) return
    if (historyWriter.running || historyReader.running) { root.saveQueued = true; return }
    root.writingRev = root.diskRev + 1
    var body = JSON.stringify(root.history)
    // Ensure rev is first key for grep-friendly writes
    var payload = '{"rev":' + root.writingRev + ',' + body.slice(1)
    historyWriter.command = ["bash", "-c",
      'mkdir -p "$0" || exit 1; '
      + 'if [ -f "$1" ] && [ ! -L "$1" ]; then cur=$(head -c 64 "$1" | sed -n \'s/^{ *"rev": *\\([0-9]*\\).*/\\1/p\'); '
      + '  [ -n "$cur" ] && [ "$cur" -ge "$3" ] && exit 3; fi; '
      + 'tmp=$(mktemp "$0/.duolingo.XXXXXXXX") && printf \'%s\' "$2" > "$tmp" '
      + '&& mv -f "$tmp" "$1" || { rm -f "$tmp"; exit 1; }',
      root.stateDir, root.stateFilePath, payload, String(root.writingRev)]
    historyWriter.running = true
  }

  IpcHandler {
    target: "user.duolingo"

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

    function toggle(): string {
      root.requestPanelToggle()
      return "Toggling panel…"
    }

    function overlay(): string {
      root.openOverlay()
      return "Opening overlay…"
    }

    function run(line: string): string {
      return root.runCommand(line)
    }
  }
}
