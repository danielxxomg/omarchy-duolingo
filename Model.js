.pragma library

function pad2(n) { return (n < 10 ? "0" : "") + n }

function dayKey(date) {
  var d = date || new Date()
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

var FLAG_MAP = {
  "en": "🇬🇧",
  "es": "🇪🇸",
  "fr": "🇫🇷",
  "de": "🇩🇪",
  "it": "🇮🇹",
  "pt": "🇧🇷",
  "ja": "🇯🇵",
  "zh": "🇨🇳",
  "ko": "🇰🇷",
  "ru": "🇷🇺",
  "nl": "🇳🇱",
  "pl": "🇵🇱",
  "sv": "🇸🇪",
  "el": "🇬🇷",
  "tr": "🇹🇷",
  "uk": "🇺🇦",
  "vi": "🇻🇳",
  "ar": "🇸🇦",
  "hi": "🇮🇳",
  "eo": "🟢",
  "la": "🏛️",
  "he": "🇮🇱",
  "ga": "🇮🇪",
  "da": "🇩🇰",
  "no": "🇳🇴",
  "fi": "🇫🇮",
  "cs": "🇨🇿",
  "ro": "🇷🇴",
  "hu": "🇭🇺",
  "id": "🇮🇩",
  "th": "🇹🇭"
}

function getLanguageFlag(code) {
  if (!code) return "🌐"
  var clean = code.toLowerCase().trim()
  return FLAG_MAP[clean] || "🌐"
}

function parseUserData(rawText) {
  if (!rawText || typeof rawText !== "string") {
    return { valid: false, error: "Empty response from Duolingo" }
  }

  try {
    var parsed = JSON.parse(rawText)

    // Normalized helper output (fetch-duo.py v1.5.0+): already validated and
    // projected upstream-side; pass through with course-shape guarantees.
    if (parsed && parsed.valid === true && Array.isArray(parsed.courses)) {
      var courses = []
      for (var k = 0; k < parsed.courses.length; k++) {
        var c = parsed.courses[k]
        courses.push({
          title: c.title || "Language",
          learningLanguage: c.learningLanguage || "",
          flag: c.flag || getLanguageFlag(c.learningLanguage),
          xp: parseInt(c.xp, 10) || 0,
          crowns: parseInt(c.crowns, 10) || 0,
          fraction: typeof c.fraction === "number" ? Math.max(0, Math.min(1, c.fraction)) : 0
        })
      }
      return {
        valid: true,
        username: parsed.username || "",
        fullname: parsed.fullname || parsed.username || "Duolingo Learner",
        streak: parseInt(parsed.streak, 10) || 0,
        streakExtendedToday: parsed.streakExtendedToday === true,
        totalXp: parseInt(parsed.totalXp, 10) || 0,
        avatar: parsed.avatar || "",
        courses: courses,
        topCourse: courses.length > 0 ? courses[0] : { title: "Language", xp: 0, flag: "🌐" },
        coursesCount: courses.length,
        lastUpdated: parsed.lastUpdated || new Date().toISOString()
      }
    }

    if (!parsed || !parsed.users || parsed.users.length === 0) {
      if (parsed && parsed.valid === false && parsed.error) {
        return { valid: false, error: String(parsed.error) }
      }
      return { valid: false, error: "User not found on Duolingo" }
    }

    var user = parsed.users[0]
    var rawCourses = Array.isArray(user.courses) ? user.courses : []
    
    // Sort courses by XP descending
    var courses = []
    var maxCourseXp = 1
    for (var i = 0; i < rawCourses.length; i++) {
      var c = rawCourses[i]
      var xpVal = parseInt(c.xp, 10) || 0
      if (xpVal > maxCourseXp) maxCourseXp = xpVal
      courses.push({
        title: c.title || "Language",
        learningLanguage: c.learningLanguage || "",
        flag: getLanguageFlag(c.learningLanguage),
        xp: xpVal,
        crowns: parseInt(c.crowns, 10) || 0
      })
    }
    courses.sort(function(a, b) { return b.xp - a.xp })

    // Calculate fraction for each course
    for (var j = 0; j < courses.length; j++) {
      courses[j].fraction = maxCourseXp > 0 ? (courses[j].xp / maxCourseXp) : 0
    }

    var topCourse = courses.length > 0 ? courses[0] : { title: "Language", xp: 0, flag: "🌐" }

    return {
      valid: true,
      username: user.username || "",
      fullname: user.name || user.fullname || user.username || "Duolingo Learner",
      streak: parseInt(user.streak, 10) || 0,
      streakExtendedToday: Boolean(user.streak_extended_today),
      totalXp: parseInt(user.totalXp, 10) || 0,
      avatar: user.picture ? (user.picture.startsWith("//") ? "https:" + user.picture : user.picture) : "",
      courses: courses,
      topCourse: topCourse,
      coursesCount: courses.length,
      lastUpdated: new Date().toISOString()
    }
  } catch (err) {
    return { valid: false, error: "JSON parse failed: " + err.message }
  }
}

function formatNumber(num) {
  if (num === null || num === undefined || isNaN(num)) return "0"
  return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

function barText(data, showXp) {
  if (!data || !data.valid) return "Duo"
  if (showXp) return formatNumber(data.totalXp) + " XP"
  return String(data.streak)
}

function tooltipText(data) {
  if (!data || !data.valid) return "Duolingo: Set your username in settings."
  var status = data.streakExtendedToday ? "Streak completed for today" : "Daily lesson pending"
  return "Duolingo (@" + data.username + ") · " + data.streak + " day streak · " + formatNumber(data.totalXp) + " XP · " + status
}

function statusSummary(data) {
  if (!data || !data.valid) return "Duolingo: Disconnected or user not configured."
  var state = data.streakExtendedToday ? "Completed" : "Pending"
  return "@" + data.username + " | Streak: " + data.streak + " days (" + state + ") | Total XP: " + formatNumber(data.totalXp) + " | Top Course: " + data.topCourse.title + " (" + formatNumber(data.topCourse.xp) + " XP)"
}

// ---------------------------------------------------------------------------
// History persistence (Service owns the file, Model owns the shape)
// Schema: {"rev": N, "days": {"YYYY-MM-DD": {"streak": int, "totalXp": int, "courses": {"<lang>": {"xp": int, "crowns": int}}}}, "updatedAt": iso}
// Pruned to last 366 entries on each commit.

var HISTORY_KEEP_DAYS = 366

function emptyHistory() {
  return { rev: 0, days: {}, updatedAt: new Date().toISOString() }
}

function keyToDate(key) {
  var p = String(key).split("-")
  return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
}

function shiftDay(date, days) {
  var d = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  d.setDate(d.getDate() + days)
  return d
}

function pruneHistory(days, todayKey) {
  var today = keyToDate(todayKey)
  var oldest = dayKey(shiftDay(today, -(HISTORY_KEEP_DAYS - 1)))
  var out = {}
  for (var k in days) {
    if (k < oldest) continue
    if (!/^\d{4}-\d{2}-\d{2}$/.test(k)) continue
    out[k] = days[k]
  }
  return out
}

function normalizeHistory(raw) {
  var out = emptyHistory()
  if (!raw || typeof raw !== "object") return out
  var revVal = Math.max(0, Math.round(Number(raw.rev)) || 0)
  out.rev = revVal
  if (raw.updatedAt && typeof raw.updatedAt === "string") out.updatedAt = raw.updatedAt
  if (raw.days && typeof raw.days === "object") {
    for (var key in raw.days) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) continue
      var day = raw.days[key]
      if (!day || typeof day !== "object") continue
      var streak = Math.max(0, Math.round(Number(day.streak)) || 0)
      var totalXp = Math.max(0, Math.round(Number(day.totalXp)) || 0)
      // firstTotalXp is optional; preserve if present to support mid-day-install delta
      var firstTotalXp = day.firstTotalXp !== undefined ? Math.max(0, Math.round(Number(day.firstTotalXp)) || 0) : totalXp
      var courses = {}
      if (day.courses && typeof day.courses === "object") {
        for (var lang in day.courses) {
          var c = day.courses[lang]
          if (!c || typeof c !== "object") continue
          var xp = Math.max(0, Math.round(Number(c.xp)) || 0)
          var crowns = Math.max(0, Math.round(Number(c.crowns)) || 0)
          courses[String(lang)] = { xp: xp, crowns: crowns }
        }
      }
      var streakExtendedToday = day.streakExtendedToday === true
      out.days[key] = { streak: streak, totalXp: totalXp, firstTotalXp: firstTotalXp, courses: courses, streakExtendedToday: streakExtendedToday }
      // keep minimal shape if firstTotalXp equals totalXp we still store it for clarity
    }
  }
  // Prune on normalize as safety; uses todayKey from latest day or today
  var todayK = dayKey(new Date())
  out.days = pruneHistory(out.days, todayK)
  return out
}

// xpToday: current totalXp minus latest snapshot with dayKey < today;
// if none exists, minus today's first snapshot (preserved as firstTotalXp);
// if no history at all, 0.
// Limitation: if installed mid-day, xpToday shows XP since install, not since midnight,
// because there is no midnight baseline. Documented here for honesty.
function xpToday(userData, history) {
  if (!userData || !userData.valid) return 0
  var current = Math.max(0, Math.round(Number(userData.totalXp)) || 0)
  if (!history || !history.days || typeof history.days !== "object") return 0
  var today = dayKey(new Date())
  var keys = Object.keys(history.days).sort()
  if (keys.length === 0) return 0
  var latestPrior = null
  for (var i = keys.length - 1; i >= 0; i--) {
    if (keys[i] < today) { latestPrior = keys[i]; break }
  }
  if (latestPrior !== null) {
    var priorTotal = Number(history.days[latestPrior].totalXp) || 0
    var diff = current - priorTotal
    return diff > 0 ? diff : 0
  }
  // No prior day: use today's first snapshot if present
  if (history.days[today]) {
    var entry = history.days[today]
    var base = entry.firstTotalXp !== undefined ? Number(entry.firstTotalXp) : Number(entry.totalXp)
    if (!isFinite(base)) base = 0
    var d = current - base
    return d > 0 ? d : 0
  }
  return 0
}

// weekHistory: last 7 days [{dayKey, letter (M/T/W/T/F/S/S), xpEarned, streakAtDay}]
// xpEarned uses same delta logic per day from snapshots (day total minus prior day total).
function weekHistory(history) {
  var out = []
  var today = new Date()
  var letters = ["S", "M", "T", "W", "T", "F", "S"]
  var daysMap = history && history.days ? history.days : {}
  var sortedKeys = Object.keys(daysMap).sort()
  for (var i = 6; i >= 0; i--) {
    var d = shiftDay(today, -i)
    var key = dayKey(d)
    var letter = letters[d.getDay()]
    var entry = daysMap[key]
    var xpEarned = 0
    var streakAtDay = entry ? (Number(entry.streak) || 0) : 0
    if (entry) {
      var prior = null
      for (var j = sortedKeys.length - 1; j >= 0; j--) {
        if (sortedKeys[j] < key) { prior = sortedKeys[j]; break }
      }
      if (prior !== null) {
        var curTotal = Number(entry.totalXp) || 0
        var priorTotal = Number(daysMap[prior].totalXp) || 0
        var diff = curTotal - priorTotal
        xpEarned = diff > 0 ? diff : 0
      } else {
        // First tracked day: xpEarned stays 0 for honesty (no baseline before tracking)
        xpEarned = 0
      }
    }
    out.push({ dayKey: key, letter: letter, xpEarned: xpEarned, streakAtDay: streakAtDay, hasData: !!entry, today: i === 0 })
  }
  return out
}

function fraction(n, d) {
  if (!d) return 0
  return Math.max(0, Math.min(1, (Number(n) || 0) / d))
}
