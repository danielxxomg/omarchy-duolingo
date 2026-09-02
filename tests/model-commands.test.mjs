#!/usr/bin/env node
// Tests for Model.js and Commands.js (the QML-side contracts).
// Guards against the v1.5.0 class of break: helper output changed while the
// QML consumer kept the old contract.
// Run: node --test tests/model-commands.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

// Load a .pragma library file into a sandbox and return its exports object.
function loadLibrary(name) {
  const exports = {};
  let src = readFileSync(join(ROOT, name), "utf8");
  src = src.replace(/^\.pragma library.*$/m, "");
  if (/^\.import\s+"Model\.js"\s+as\s+Model/m.test(src)) {
    src = src.replace(/^\.import\s+"Model\.js"\s+as\s+Model.*$/m, "const Model = __model;");
  }
  new Function("__exports", "__model", src + "\n;Object.assign(__exports, { dayKey, pad2, FLAG_MAP, getLanguageFlag, parseUserData, formatNumber, barText, tooltipText, statusSummary, emptyHistory, pruneHistory, normalizeHistory, xpToday, weekHistory, fraction })")(exports, model);
  return exports;
}

const model = (() => {
  const exports = {};
  loadLibraryInto(exports, "Model.js");
  return exports;
})();

function loadLibraryInto(exports, name) {
  let src = readFileSync(join(ROOT, name), "utf8");
  src = src.replace(/^\.pragma library.*$/m, "");
  const fn = new Function("__exports", src + `
    ;Object.assign(__exports, { pad2, dayKey, FLAG_MAP, getLanguageFlag, parseUserData,
      formatNumber, barText, tooltipText, statusSummary, emptyHistory, keyToDate,
      shiftDay, pruneHistory, normalizeHistory, xpToday, weekHistory, fraction })`);
  fn(exports);
}

// Commands.js needs Model injected; provide via the same Function trick.
function loadCommands() {
  let src = readFileSync(join(ROOT, "Commands.js"), "utf8");
  src = src.replace(/^\.pragma library.*$/m, "");
  src = src.replace(/^\.import\s+"Model\.js"\s+as\s+Model.*$/m, "const Model = __model;");
  const fn = new Function("__exports", "__model", src + `
    ;Object.assign(__exports, { USERNAME_RE, clampGoal, isBareNumber, parseGoalNumber,
      VERBS, verbNamed, score, verbScore, split, args, suggest, row, parse,
      execute, contextOf, helpRows })`);
  const exports = {};
  fn(exports, model);
  return exports;
}

const commands = loadCommands();

const NORMALIZED = {
  valid: true,
  username: "emma_learn",
  fullname: "emma_learn",
  avatar: "",
  streak: 12,
  streakExtendedToday: true,
  totalXp: 5000,
  courses: [
    { title: "Spanish", learningLanguage: "es", xp: 4000, crowns: 20, flag: "🇪🇸", fraction: 1.0 },
    { title: "Japanese", learningLanguage: "ja", xp: 1000, crowns: 5, flag: "🇯🇵", fraction: 0.25 },
  ],
  topCourse: { title: "Spanish", learningLanguage: "es", xp: 4000, crowns: 20, flag: "🇪🇸", fraction: 1.0 },
  coursesCount: 2,
  lastUpdated: "2026-09-02T20:00:00Z",
};

// --- Model.parseUserData: normalized contract -------------------------------

test("parseUserData accepts the normalized helper document", () => {
  const r = model.parseUserData(JSON.stringify(NORMALIZED));
  assert.equal(r.valid, true);
  assert.equal(r.username, "emma_learn");
  assert.equal(r.streak, 12);
  assert.equal(r.streakExtendedToday, true);
  assert.equal(r.courses[0].flag, "🇪🇸");
  assert.equal(r.courses[1].fraction, 0.25);
});

test("parseUserData surfaces helper error strings", () => {
  const r = model.parseUserData(JSON.stringify({ valid: false, error: "Network error fetching Duolingo data" }));
  assert.equal(r.valid, false);
  assert.equal(r.error, "Network error fetching Duolingo data");
});

test("parseUserData keeps legacy users[] shape working", () => {
  const raw = { users: [{ username: "x", name: "Old", streak: 3, totalXp: 500, picture: "//p", courses: [{ title: "Spanish", learningLanguage: "es", xp: 400, crowns: 9 }] }] };
  const r = model.parseUserData(JSON.stringify(raw));
  assert.equal(r.valid, true);
  assert.equal(r.fullname, "Old");
  assert.equal(r.courses[0].flag, "🇪🇸");
});

test("parseUserData rejects empty input", () => {
  assert.equal(model.parseUserData("").valid, false);
  assert.equal(model.parseUserData(null).valid, false);
  assert.equal(model.parseUserData("not json").valid, false);
});

// --- Model history math ------------------------------------------------------

test("xpToday uses latest prior day baseline", () => {
  const today = model.dayKey(new Date());
  const yesterday = model.dayKey(model.shiftDay(new Date(), -1));
  const h = model.normalizeHistory({
    rev: 3,
    days: {
      [yesterday]: { streak: 5, totalXp: 1000, courses: {} },
      [today]: { streak: 6, totalXp: 1050, courses: {} },
    },
  });
  const userData = { valid: true, totalXp: 1100 };
  assert.equal(model.xpToday(userData, h), 100);
});

test("xpToday is zero without history", () => {
  assert.equal(model.xpToday({ valid: true, totalXp: 999 }, model.emptyHistory()), 0);
});

test("normalizeHistory clamps negative and malformed values", () => {
  const h = model.normalizeHistory({ rev: -5, days: { "2026-09-01": { streak: -3, totalXp: "abc", courses: { en: { xp: -1, crowns: 2 } } } } });
  assert.equal(h.rev, 0);
  const day = h.days["2026-09-01"];
  assert.equal(day.streak, 0);
  assert.equal(day.totalXp, 0);
  assert.equal(day.courses.en.xp, 0);
  assert.equal(day.courses.en.crowns, 2);
});

test("pruneHistory drops keys older than 366 days", () => {
  const today = model.dayKey(new Date());
  const ancient = model.dayKey(model.shiftDay(new Date(), -400));
  const out = model.pruneHistory({ [ancient]: {}, [today]: {} }, today);
  assert.deepEqual(Object.keys(out), [today]);
});

// --- Model presentation ------------------------------------------------------

test("barText shows streak or xp", () => {
  assert.equal(model.barText({ valid: true, streak: 7, totalXp: 1234 }, false), "7");
  assert.equal(model.barText({ valid: true, streak: 7, totalXp: 1234 }, true), "1,234 XP");
  assert.equal(model.barText({ valid: false }, false), "Duo");
});

test("formatNumber adds thousands separators", () => {
  assert.equal(model.formatNumber(1234567), "1,234,567");
  assert.equal(model.formatNumber(999), "999");
});

// --- Commands grammar ---------------------------------------------------------

const ctx = {
  hasData: true,
  username: "emma_learn",
  streak: 12,
  totalXp: 5000,
  xpToday: 30,
  goalXp: 50,
  goalFraction: 1.0,
  goalMet: false,
  streakExtendedToday: false,
  topCourse: { title: "Spanish", xp: 4000 },
};

test("parse recognizes verbs and aliases", () => {
  assert.equal(commands.parse("practice", ctx).ok, true);
  assert.equal(commands.parse("p", ctx).verb, "practice");
  assert.equal(commands.parse("refresh stats", ctx).verb, "refresh");
  assert.equal(commands.parse("t", ctx).verb, "today");
});

test("parse treats prefix typos as completion, rejects unknown verbs", () => {
  // "practic" is a prefix of "practice" -> fuzzy matching executes it (by design)
  assert.equal(commands.parse("practic", ctx).verb, "practice");
  // A genuinely unknown verb is rejected
  const r = commands.parse("xyzzy", ctx);
  assert.equal(r.ok, false);
  assert.match(r.error, /No command called "xyzzy"/);
});

test("bare number maps to goal verb", () => {
  const r = commands.parse("100", ctx);
  assert.equal(r.ok, true);
  assert.equal(r.verb, "goal");
  const bad = commands.parse("9999", ctx);
  assert.equal(bad.ok, false);
  assert.equal(typeof bad.error, "string");
});

test("goal validates range", () => {
  assert.equal(commands.parse("goal 5", ctx).ok, false);
  assert.equal(commands.parse("goal 2000", ctx).ok, false);
  assert.equal(commands.parse("goal 250", ctx).ok, true);
  assert.equal(commands.parse("goal", ctx).ok, false);
});

test("username validates format", () => {
  assert.equal(commands.parse("username emma!", ctx).ok, false);
  assert.equal(commands.parse("username", ctx).ok, false);
  assert.equal(commands.parse("username Emma_Learns", ctx).ok, true);
});

test("suggest ranks exact match above fuzzy", () => {
  const rows = commands.suggest("streak", ctx);
  assert.equal(rows[0].verb, "streak");
});

test("suggest empty input returns starters", () => {
  const rows = commands.suggest("", ctx);
  assert.ok(rows.length > 0);
  assert.equal(rows[0].verb, "practice");
});

test("contextOf handles missing service", () => {
  const c = commands.contextOf(null);
  assert.equal(c.hasData, false);
  assert.equal(c.goalXp, 50);
});

test("helpRows include every verb with arg hints", () => {
  const rows = commands.helpRows();
  const names = rows.map((r) => r.name);
  assert.ok(names.some((n) => n.startsWith("goal <number>")));
  assert.ok(names.some((n) => n.startsWith("username <name>")));
});