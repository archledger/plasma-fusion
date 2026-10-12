// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/date-timer.js (not installed). Run: node tests/date-timer.test.js
// The 2026-10-06 case: Qt timers pause across system suspend, so one long "next midnight"
// interval left the calendar tile on yesterday's date for hours after resume.
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "date-timer.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const changed = globalThis.changed;
const intervalTo = globalThis.intervalTo;
const CAP_MS = globalThis.CAP_MS;
assert.notStrictEqual(changed, undefined, "date-timer.js does not define changed");
assert.notStrictEqual(intervalTo, undefined, "date-timer.js does not define intervalTo");

// changed(): same day false; midnight, month and year rollovers true
assert.strictEqual(changed(new Date(2026, 9, 6, 2, 14), new Date(2026, 9, 6, 23, 59)), false, "same day");
assert.strictEqual(changed(new Date(2026, 9, 5, 2, 1), new Date(2026, 9, 6, 0, 0, 6)), true, "midnight rollover");
assert.strictEqual(changed(new Date(2026, 9, 31, 23, 59), new Date(2026, 10, 1, 0, 0, 6)), true, "month rollover");
assert.strictEqual(changed(new Date(2026, 11, 31, 23, 59), new Date(2027, 0, 1, 0, 0, 6)), true, "year rollover");
// the stale-day case: the shell was created on the 5th and the check runs on the 6th
assert.strictEqual(changed(new Date(2026, 9, 5, 2, 0), new Date(2026, 9, 6, 2, 14)), true, "stale creation day");
// same day number in a later month must still count as changed (month blind spot)
assert.strictEqual(changed(new Date(2026, 1, 6), new Date(2026, 2, 6)), true, "same day number, next month");

// intervalTo(): the exact pre-midnight case keeps the original 00:00:05 fire point
assert.strictEqual(intervalTo(new Date(2026, 9, 5, 23, 59, 0), CAP_MS), 65000, "one minute before midnight");
// the regression: mid-day intervals must never exceed the cap (the old code armed ~14 h ahead;
// after suspend that fire landed hours late and the tile showed yesterday)
for (const h of [0, 1, 8, 10, 12, 18, 22, 23]) {
    const at = new Date(2026, 9, 6, h, 17, 33);
    const raw = new Date(2026, 9, 7, 0, 0, 5) - at;
    const got = intervalTo(at, CAP_MS);
    assert.ok(got <= CAP_MS, `uncapped interval at ${h}:00 (${got} > ${CAP_MS}; raw ${raw})`);
    assert.strictEqual(got, Math.max(1000, Math.min(raw, CAP_MS)), `interval at ${h}:00`);
}
// just before midnight keeps the exact 00:00:05 fire point (below the cap)
assert.strictEqual(intervalTo(new Date(2026, 9, 5, 23, 59, 58), CAP_MS), 7000, "two seconds before midnight");

console.log("date-timer: all checks passed");
