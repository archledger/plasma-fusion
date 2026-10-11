// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/keepawake.js (not installed). Run: TZ=Europe/Berlin node tests/keepawake.test.js
"use strict";
process.env.TZ = process.env.TZ || "Europe/Berlin";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "keepawake.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { untilTime, defaultUntil, minutesLeft, nextCheck, MINUTE, HOUR } = globalThis;

const at = (y, mo, d, h, mi, s) => new Date(y, mo - 1, d, h, mi, s || 0);
// "Until a time": today while it is ahead, else tomorrow; whole minutes of the day.
assert.strictEqual(untilTime(at(2026, 10, 11, 14, 10), 17 * 60 + 30), at(2026, 10, 11, 17, 30).getTime(), "later today");
assert.strictEqual(untilTime(at(2026, 10, 11, 23, 0), 7 * 60), at(2026, 10, 12, 7, 0).getTime(), "a time already passed: tomorrow");
assert.strictEqual(untilTime(at(2026, 10, 11, 7, 0), 7 * 60), at(2026, 10, 12, 7, 0).getTime(), "now: tomorrow, not an instant end");
assert.strictEqual(untilTime(at(2026, 10, 11, 22, 0), 24 * 60), at(2026, 10, 12, 0, 0).getTime(), "24:00 is midnight");
// Across the end of summer time (Europe, 2026-10-25 03:00 -> 02:00) it is still the local time.
assert.strictEqual(untilTime(at(2026, 10, 24, 23, 0), 9 * 60), at(2026, 10, 25, 9, 0).getTime(), "across a clock change: local 09:00");
assert.strictEqual(untilTime(at(2026, 10, 24, 23, 0), 9 * 60) - at(2026, 10, 24, 23, 0).getTime(), 11 * HOUR, "which is 11 hours away");

assert.strictEqual(defaultUntil(at(2026, 10, 11, 14, 10)), 15 * 60 + 15, "first offer: the quarter hour after an hour from now");
assert.strictEqual(defaultUntil(at(2026, 10, 11, 14, 15)), 15 * 60 + 15, "on a quarter hour: exactly an hour later");
assert.strictEqual(defaultUntil(at(2026, 10, 11, 14, 15, 1)), 15 * 60 + 30, "a second past: the next one");
assert.strictEqual(defaultUntil(at(2026, 10, 11, 23, 50)), 1 * 60, "past midnight wraps");

const t0 = at(2026, 10, 11, 14, 0).getTime();
assert.strictEqual(minutesLeft(t0, t0 + HOUR), 60, "an hour left: 60 minutes");
assert.strictEqual(minutesLeft(t0, t0 + 1000), 1, "a second left still shows a minute");
assert.strictEqual(minutesLeft(t0, t0 + 61000), 2, "rounded up");
assert.strictEqual(minutesLeft(t0, t0), 0, "up: none left");
assert.strictEqual(minutesLeft(t0, t0 - 5000), 0, "past (after a suspend): none left");

assert.strictEqual(nextCheck(t0, t0 + 4 * HOUR), MINUTE, "a whole number of minutes left: look again in a minute");
assert.strictEqual(nextCheck(t0, t0 + 61000), 1000, "look again when the minutes shown change");
assert.strictEqual(nextCheck(t0, t0 + 3000), 3000, "or when the time is up");
assert.strictEqual(nextCheck(t0, t0), 0, "up now");
assert.strictEqual(nextCheck(t0, t0 - HOUR), 0, "long past");
console.log("keepawake: all checks passed");
