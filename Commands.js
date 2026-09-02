// Command grammar for the Duolingo overlay and `omarchy-shell user.duolingo run "..."`.
// Pure functions: parse text into an action, rank suggestions for a partial line,
// and describe what a line would do before it runs. Mirrors the contract from
// ryanyogan.hydrate's Commands.js so Overlay and Service can stay thin.
.pragma library
.import "Model.js" as Model

// ---------------------------------------------------------------------------
// Helpers

var USERNAME_RE = /^[A-Za-z0-9_.-]{2,25}$/

function clampGoal(n) {
  var v = Math.round(Number(n))
  if (!isFinite(v)) return 0
  return Math.max(10, Math.min(1000, v))
}

function isBareNumber(text) {
  var t = String(text || "").trim()
  if (!t) return false
  return /^\d+$/.test(t)
}

function parseGoalNumber(text) {
  var m = /^\s*(\d+)\s*$/.exec(String(text || ""))
  if (!m) return 0
  var n = parseInt(m[1], 10)
  if (!isFinite(n)) return 0
  if (n < 10 || n > 1000) return 0
  return n
}

// ---------------------------------------------------------------------------
// Verbs
//
// Each entry mirrors hydrate's shape {name, aliases, hint, preview(ctx,a), run(s,a), arg, ui, valid, confirm}
var VERBS = [
  { name: "practice", aliases: ["p", "learn", "go"], hint: "Launch Duolingo",
    preview: function(ctx, a) {
      if (a.rest) return "Launch Duolingo" + (a.rest ? " (" + a.rest + ")" : "")
      return "Launch Duolingo"
    },
    run: function(s, a) { if (s && typeof s.launchDuolingo === "function") s.launchDuolingo(); else if (s && s.bar) s.bar.run((s.pluginDir || "") + "/bin/launch-duo.sh"); return "Launching Duolingo..." }
  },

  { name: "refresh", aliases: ["r", "reload", "sync"], hint: "Refresh stats from Duolingo",
    preview: function() { return "Refresh stats from Duolingo" },
    run: function(s) { if (s && typeof s.refresh === "function") s.refresh(); return "Refreshing Duolingo stats..." }
  },

  { name: "open", aliases: ["panel"], hint: "Open the dropdown panel", ui: "close",
    preview: function() { return "Open panel" },
    run: function(s) { if (s.requestPanelOpen) s.requestPanelOpen() }
  },

  { name: "username", aliases: ["user", "name", "u"], arg: "name", hint: "Set Duolingo username, e.g. username duo_learner",
    preview: function(ctx, a) {
      var w = String(a.word || a.rest || "").trim()
      if (!w) return "Needs a username, like username duo_learner"
      if (!USERNAME_RE.test(w)) return "Username must match ^[A-Za-z0-9_.-]{2,25}$"
      if (ctx.username && ctx.username === w) return "Username already @" + w
      return "Set username to @" + w
    },
    run: function(s, a) {
      var w = String(a.word || a.rest || "").trim()
      if (!USERNAME_RE.test(w)) return "Username must match ^[A-Za-z0-9_.-]{2,25}$"
      if (s && typeof s.setUsername === "function") s.setUsername(w)
      else if (s && typeof s.persistUsername === "function") s.persistUsername(w)
      return "Username set to @" + w
    },
    valid: function(a) { var w = String(a.word || a.rest || "").trim(); return USERNAME_RE.test(w) }
  },

  { name: "goal", aliases: ["target"], arg: "number", hint: "Set daily XP goal, e.g. goal 100",
    preview: function(ctx, a) {
      var n = a.n || parseGoalNumber(a.rest)
      if (!n) {
        if (!String(a.rest || "").trim()) return "Needs a number 10-1000, like goal 100"
        return "Goal must be 10-1000"
      }
      return "Daily goal " + n + " XP" + (ctx.goalXp === n ? " (already set)" : "")
    },
    run: function(s, a) {
      var n = a.n || parseGoalNumber(a.rest)
      if (!n) return "Goal must be 10-1000"
      n = clampGoal(n)
      if (s && typeof s.setGoal === "function") s.setGoal(n)
      else if (s && typeof s.setSetting === "function") s.setSetting("goalXp", n)
      return "Daily goal set to " + n + " XP"
    },
    valid: function(a) { var n = a.n || parseGoalNumber(a.rest); return !!n }
  },

  { name: "streak", aliases: [], hint: "Show current streak",
    preview: function(ctx) {
      if (!ctx.hasData) return "No Duolingo data yet"
      return "Streak: " + ctx.streak + " days" + (ctx.streakExtendedToday ? " — done today" : " — pending today")
    },
    run: function(s, a) {
      var ctx = contextOf(s)
      if (!ctx.hasData) return "No Duolingo data yet"
      return "Streak: " + ctx.streak + " days" + (ctx.streakExtendedToday ? " — done today" : " — pending today")
    }
  },

  { name: "xp", aliases: [], hint: "Show total XP",
    preview: function(ctx) {
      if (!ctx.hasData) return "No Duolingo data yet"
      return "Total XP: " + Model.formatNumber(ctx.totalXp) + (ctx.topCourse ? " · Top: " + ctx.topCourse.title : "")
    },
    run: function(s) {
      var ctx = contextOf(s)
      if (!ctx.hasData) return "No Duolingo data yet"
      return "Total XP: " + Model.formatNumber(ctx.totalXp)
    }
  },

  { name: "today", aliases: ["t", "now"], hint: "Show today's progress",
    preview: function(ctx) {
      if (!ctx.hasData) return "No Duolingo data yet"
      return ctx.xpToday + " / " + ctx.goalXp + " XP today" + (ctx.goalMet ? " — goal met" : "")
    },
    run: function(s) {
      var ctx = contextOf(s)
      if (!ctx.hasData) return "No Duolingo data yet"
      return ctx.xpToday + " / " + ctx.goalXp + " XP today" + (ctx.goalMet ? " — goal met" : "")
    }
  },

  { name: "history", aliases: ["h", "log"], hint: "Show recent history", ui: "history",
    preview: function() { return "Show history" }
  },

  { name: "help", aliases: ["?"], hint: "Every command", ui: "help",
    preview: function() { return "Show every command" }
  },

  { name: "quit", aliases: ["q", "close", "exit"], hint: "Close the overlay", ui: "close",
    preview: function() { return "Close" }
  }
]

function verbNamed(name) {
  for (var i = 0; i < VERBS.length; i++) if (VERBS[i].name === name) return VERBS[i]
  return null
}

// ---------------------------------------------------------------------------
// Matching — identical to hydrate for predictable ranking

function score(query, candidate) {
  if (query === candidate) return 100
  if (candidate.indexOf(query) === 0) return 80 - (candidate.length - query.length)
  var qi = 0
  for (var ci = 0; ci < candidate.length && qi < query.length; ci++) if (candidate[ci] === query[qi]) qi++
  if (qi === query.length) return 20 + Math.round(20 * query.length / candidate.length)
  return 0
}

function verbScore(query, verb) {
  var best = score(query, verb.name)
  for (var i = 0; i < verb.aliases.length; i++) {
    var s = score(query, verb.aliases[i])
    if (s > best) best = s - 1
  }
  return best
}

function split(text) {
  var t = String(text || "").trim().replace(/\s+/g, " ")
  if (!t) return { verb: "", rest: "" }
  var sp = t.indexOf(" ")
  if (sp < 0) return { verb: t.toLowerCase(), rest: "" }
  return { verb: t.slice(0, sp).toLowerCase(), rest: t.slice(sp + 1).trim() }
}

function args(verb, rest, ctx) {
  var a = { n: 0, word: "", rest: rest, raw: rest }
  var parts = String(rest || "").trim().split(/\s+/)
  // First word, preserving original case for username
  var firstRaw = (String(rest || "").trim().split(/\s+/)[0] || "")
  a.word = firstRaw
  a.wordLower = String(firstRaw || "").toLowerCase()
  if (verb.arg === "number") {
    var n = parseInt(String(rest || "").trim(), 10)
    a.n = isFinite(n) ? clampGoal(n) : 0
    // Validate true parse: reject non-numeric or out-of-range
    var parsed = parseGoalNumber(rest)
    if (!parsed) a.n = 0
    else a.n = parsed
  }
  if (verb.arg === "name") {
    a.word = String(rest || "").trim()
    a.wordLower = a.word.toLowerCase()
  }
  return a
}

function suggest(text, ctx, limit) {
  var p = split(text)
  var out = []
  if (!p.verb) {
    var starters = ["practice", "refresh", "today", "goal", "history", "help"]
    for (var i = 0; i < starters.length && i < (limit || 6); i++) out.push(row(verbNamed(starters[i]), "", ctx))
    return out
  }
  // Bare number -> goal
  var bare = String(text || "").trim()
  if (isBareNumber(bare)) {
    var n = parseGoalNumber(bare)
    if (n) return [row(verbNamed("goal"), bare, ctx, 200)]
    // out-of-range bare number still suggests goal with hint
    return [row(verbNamed("goal"), bare, ctx, 200)]
  }
  // Also handle "goal 50" style but typed as bare number with prefix already captured as verb? No.
  // Regular verb ranking
  for (var v = 0; v < VERBS.length; v++) {
    var s = verbScore(p.verb, VERBS[v])
    if (s > 0) out.push(row(VERBS[v], p.rest, ctx, s))
  }
  out.sort(function(x, y) { return y.score - x.score })
  return out.slice(0, limit || 6)
}

function row(verb, rest, ctx, s) {
  var a = args(verb, rest, ctx)
  return {
    verb: verb.name, name: verb.name, hint: verb.hint, arg: verb.arg || "",
    completion: verb.name + (rest ? " " + rest : (verb.arg ? " " : "")),
    preview: verb.preview(ctx, a), score: s === undefined ? 0 : s,
    ui: verb.ui || ""
  }
}

function parse(text, ctx) {
  var p = split(text)
  if (!p.verb) return { ok: false, error: "" }
  // Bare number -> goal
  var bare = String(text || "").trim()
  if (isBareNumber(bare)) {
    var verb = verbNamed("goal")
    var a = args(verb, bare, ctx)
    if (verb.valid && !verb.valid(a)) return { ok: false, verb: verb.name, error: verb.preview(ctx, a) }
    return { ok: true, verb: verb.name, args: a, preview: verb.preview(ctx, a), ui: verb.ui || "", confirm: verb.confirm ? verb.confirm(a) : false }
  }
  var best = 0
  var found = null
  for (var v = 0; v < VERBS.length; v++) {
    var sc = verbScore(p.verb, VERBS[v])
    if (sc > best) { best = sc; found = VERBS[v] }
  }
  if (!found || best < 40) return { ok: false, error: "No command called \"" + p.verb + "\"" + (found ? ". Did you mean " + found.name + "?" : "") }
  var a2 = args(found, p.rest, ctx)
  if (found.arg && !String(p.rest || "").trim()) {
    // Missing required arg: surface preview as error so user knows what's needed
    if (found.valid && !found.valid(a2)) return { ok: false, verb: found.name, error: found.preview(ctx, a2) }
    // Still allow ui verbs without arg; but for arg verbs, require value
    if (found.arg === "name" || found.arg === "number") return { ok: false, verb: found.name, error: found.preview(ctx, a2) }
  }
  if (found.valid && !found.valid(a2)) return { ok: false, verb: found.name, error: found.preview(ctx, a2) }
  return { ok: true, verb: found.name, args: a2, preview: found.preview(ctx, a2), ui: found.ui || "", confirm: found.confirm ? found.confirm(a2) : false }
}

function execute(service, parsed) {
  var verb = verbNamed(parsed.verb)
  if (!verb || !verb.run) return parsed.preview || ""
  return verb.run(service, parsed.args)
}

function contextOf(service) {
  if (!service) return { hasData: false, username: "", streak: 0, totalXp: 0, xpToday: 0, goalXp: 50, goalMet: false, streakExtendedToday: false, topCourse: null, goalFraction: 0 }
  var d = service.userData
  var hasData = !!(d && d.valid)
  return {
    hasData: hasData,
    username: hasData ? String(d.username || "") : "",
    streak: hasData ? (Number(d.streak) || 0) : 0,
    totalXp: hasData ? (Number(d.totalXp) || 0) : 0,
    xpToday: service.xpToday !== undefined ? service.xpToday : 0,
    goalXp: service.goalXp !== undefined ? service.goalXp : 50,
    goalFraction: service.goalFraction !== undefined ? service.goalFraction : 0,
    goalMet: service.goalMet === true,
    streakExtendedToday: hasData ? !!d.streakExtendedToday : false,
    topCourse: hasData ? d.topCourse : null,
    configuredUsername: service.configuredUsername !== undefined ? String(service.configuredUsername || "") : ""
  }
}

function helpRows() {
  var out = []
  for (var i = 0; i < VERBS.length; i++) {
    var v = VERBS[i]
    out.push({ name: v.name + (v.arg ? " <" + v.arg + ">" : ""), aliases: v.aliases.join(", "), hint: v.hint })
  }
  return out
}
