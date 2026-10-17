// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/metrics.js (not installed): the dock's sizes (board DockSize.dc.html),
// tablet posture's metrics and the magnified size. Run: node tests/metrics.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

// As in pins.test.js: the ".pragma library" line becomes spaces, the names become globals.
const file = path.join(__dirname, "..", "contents", "code", "metrics.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { metrics, zoomTarget, size } = globalThis;

// The board's three sizes: tile, gap, separator and its slot, side and bottom padding, plate
// (padding top + tile + bottom: 8+40+12, 10+48+14, 10+56+12), indicators.
const pick = (m) => [m.tile, m.gap, m.sepLength, m.sepSlot, m.sidePad, m.bottomPad, m.plate, m.wideIndicators];
assert.deepStrictEqual(pick(metrics(0, false, 56)), [40, 7, 30, 7, 10, 12, 60, false], "Small");
assert.deepStrictEqual(pick(metrics(1, false, 56)), [48, 8, 36, 9, 12, 14, 72, false], "Medium: the Main board's dock, as before");
assert.deepStrictEqual(pick(metrics(2, false, 56)), [56, 12, 40, 13, 12, 12, 78, true], "Large: the Tablet board's dock");
// Tablet posture keeps its own metrics at its tile size, whatever the dock's size.
for (const s of [0, 1, 2]) {
    assert.deepStrictEqual(pick(metrics(s, true, 56)).slice(0, 6), [56, 12, 40, 13, 12, 12], "tablet posture, size " + s);
    assert.strictEqual(metrics(s, true, 48).tile, 48, "the tablet tile setting");
}
// A value the page does not write is Medium.
assert.deepStrictEqual([size(undefined), size(""), size(7), size("2"), size(0)], [1, 1, 1, 2, 0]);
// The table is not changed through a returned copy.
metrics(1, false, 56).tile = 99;
assert.strictEqual(metrics(1, false, 56).tile, 48);

// The magnified size: the page's +14 / +8 px (62 / 56, the Medium dock's) is the step at 48 px
// and up, smaller below (Small: 52 and 47 px, the board's); tablet posture adds 14.
assert.deepStrictEqual([zoomTarget(48, 62, false), zoomTarget(48, 56, false)], [62, 56], "Medium: 62 and 56, as before");
assert.deepStrictEqual([zoomTarget(56, 62, false), zoomTarget(56, 56, false)], [70, 64], "Large: the same step");
assert.deepStrictEqual([zoomTarget(40, 62, false), zoomTarget(40, 56, false)], [52, 47], "Small: the step shrinks with the icon");
assert.strictEqual(zoomTarget(48, 72, false), 72, "the dock's own settings go up to 72");
assert.strictEqual(zoomTarget(48, 40, false), 48, "no step below the icon");
assert.deepStrictEqual([zoomTarget(56, 56, true), zoomTarget(48, 62, true)], [70, 62], "tablet posture: +14");

console.log("metrics: all checks passed");
