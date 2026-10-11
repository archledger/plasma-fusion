// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/dnd.js (not installed). Run: node tests/dnd.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "dnd.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { untilMorning, choices, untilLabel } = globalThis;

// Local times: year, month (0-based), day, hour, minute.
const at = (d, h, m) => new Date(2026, 9, d, h, m, 0, 0);
const hours = (from, to) => (to.getTime() - from.getTime()) / 3600000;

assert.deepStrictEqual(untilMorning(at(11, 22, 30)), at(12, 6, 0), "evening: the next morning");
assert.deepStrictEqual(untilMorning(at(11, 14, 0)), at(12, 6, 0), "afternoon: the next morning");
assert.deepStrictEqual(untilMorning(at(12, 1, 0)), at(12, 6, 0), "after midnight: this coming morning");
assert.ok(hours(at(12, 1, 0), untilMorning(at(12, 1, 0))) === 5, "01:00 lasts 5 hours, not 29");
assert.deepStrictEqual(untilMorning(at(12, 0, 0)), at(12, 6, 0), "midnight: this coming morning");
assert.deepStrictEqual(untilMorning(at(12, 6, 0)), at(13, 6, 0), "06:00 exactly: the next morning");
assert.deepStrictEqual(untilMorning(at(31, 23, 0)), new Date(2026, 10, 1, 6, 0, 0, 0), "end of the month");

// The choices offered at a time: ids in order, and each end. 2026-10-11 is a Sunday.
const ids = (now) => choices(now).map((c) => c.id);
const end = (now, id) => choices(now).find((c) => c.id === id).until;
assert.deepStrictEqual(ids(at(14, 10, 15)), ["hour", "hours4", "evening", "morning", "off"], "Wednesday morning");
assert.deepStrictEqual(end(at(14, 10, 15), "hour"), at(14, 11, 15), "for 1 hour");
assert.deepStrictEqual(end(new Date(2026, 9, 14, 10, 15, 42, 500), "hour"), at(14, 11, 15), "for 1 hour: whole minutes");
assert.deepStrictEqual(end(at(14, 10, 15), "hours4"), at(14, 14, 15), "for 4 hours");
assert.deepStrictEqual(end(at(14, 22, 30), "hours4"), at(15, 2, 30), "for 4 hours past midnight");
assert.deepStrictEqual(end(at(14, 10, 15), "evening"), at(14, 20, 0), "this evening: 20:00");
assert.deepStrictEqual(ids(at(14, 20, 0)), ["hour", "hours4", "morning", "off"], "no evening from 20:00");
assert.deepStrictEqual(ids(at(14, 19, 59)).includes("evening"), true, "evening until 19:59");
assert.deepStrictEqual(end(at(14, 10, 15), "morning"), at(15, 6, 0), "tomorrow morning");
assert.deepStrictEqual(end(at(15, 2, 0), "morning"), at(15, 6, 0), "after midnight: this coming morning");
assert.deepStrictEqual(ids(at(16, 9, 0)), ["hour", "hours4", "evening", "morning", "monday", "off"], "Friday: Monday too");
assert.deepStrictEqual(end(at(16, 9, 0), "monday"), at(19, 6, 0), "Friday: next Monday 06:00");
assert.deepStrictEqual(end(at(17, 23, 0), "monday"), at(19, 6, 0), "Saturday: next Monday 06:00");
assert.deepStrictEqual(end(new Date(2026, 9, 31, 12, 0), "monday"), new Date(2026, 10, 2, 6, 0), "Saturday at the end of the month");
assert.ok(!ids(at(11, 12, 0)).includes("monday"), "Sunday: tomorrow morning is Monday morning, no Monday choice");
assert.ok(!ids(at(12, 12, 0)).includes("monday"), "Monday: no Monday choice");
assert.deepStrictEqual(end(at(14, 10, 15), "off"), new Date(2027, 9, 14, 10, 15), "until turned off: a year ahead");

// The end shown, and when it has to be shown again.
const now = at(14, 10, 0).getTime();
const label = (d) => untilLabel(d, now);
assert.deepStrictEqual(label(undefined), { kind: "none", refreshAt: -1 }, "no end set");
assert.deepStrictEqual(label(new Date(NaN)), { kind: "none", refreshAt: -1 }, "invalid end");
assert.deepStrictEqual(label(at(14, 9, 0)), { kind: "none", refreshAt: -1 }, "end passed");
assert.deepStrictEqual(label(at(14, 18, 0)), { kind: "time", refreshAt: at(14, 18, 0).getTime() }, "today: the time, until it ends");
assert.deepStrictEqual(label(at(15, 9, 59)), { kind: "time", refreshAt: at(15, 9, 59).getTime() }, "23:59 ahead: the time");
assert.deepStrictEqual(label(at(16, 6, 0)), { kind: "day", refreshAt: at(15, 6, 0).getTime() }, "two days ahead: day and time, the time from 24 h before");
assert.deepStrictEqual(label(at(25, 6, 0)).kind, "date", "eleven days ahead: the date");
assert.deepStrictEqual(label(at(25, 6, 0)).refreshAt, at(18, 6, 0).getTime(), "the date until a week before");
const year = new Date(2027, 9, 14, 10, 0);
assert.deepStrictEqual(label(year).kind, "none", "until turned off: no end shown");
assert.ok(label(year).refreshAt > now, "until turned off: looked at again only 100 days before");
// The subtitle follows the clock: a Do Not Disturb until Monday shows the day, then the time.
const monday = end(at(16, 9, 0), "monday");
const first = untilLabel(monday, at(16, 9, 0).getTime());
assert.strictEqual(first.kind, "day", "Friday: Monday's end shows the day");
assert.strictEqual(untilLabel(monday, first.refreshAt).kind, "time", "a day before the end: the time");
assert.strictEqual(untilLabel(monday, monday.getTime()).kind, "none", "at the end: nothing");

console.log("dnd: all checks passed");
