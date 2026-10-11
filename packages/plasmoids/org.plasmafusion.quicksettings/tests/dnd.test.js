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
const { untilMorning } = globalThis;

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
console.log("dnd: all checks passed");
