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
    if (!parsed || !parsed.users || parsed.users.length === 0) {
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
  if (!data || !data.valid) return "󰂚 Duo"
  if (showXp) return "󰂚 " + formatNumber(data.totalXp) + " XP"
  return "🔥 " + data.streak
}

function tooltipText(data) {
  if (!data || !data.valid) return "Duolingo: Detecting user account…"
  var status = data.streakExtendedToday ? "Streak saved today! 🎉" : "Daily lesson pending! ⚠️"
  return "Duolingo (@" + data.username + ") · " + data.streak + " day streak · " + formatNumber(data.totalXp) + " XP · " + status
}

function statusSummary(data) {
  if (!data || !data.valid) return "Duolingo: Disconnected or user not configured."
  var state = data.streakExtendedToday ? "Completed" : "Pending"
  return "@" + data.username + " | Streak: " + data.streak + " days (" + state + ") | Total XP: " + formatNumber(data.totalXp) + " | Top Course: " + data.topCourse.title + " (" + formatNumber(data.topCourse.xp) + " XP)"
}
