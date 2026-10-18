// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of sideFor() in plasmafusion-tablet's Snap.js: the half a window takes when Full screen is
// switched off in tablet posture (board TabletSnap.dc.html). Run: node tests/tablet-snap.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");
const file = path.join(__dirname, "..", "scripts", "plasmafusion-tablet", "contents", "ui", "Snap.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { sideFor, isLeft, isRight } = globalThis;
assert.strictEqual(typeof sideFor, "function", "Snap.js does not define sideFor");

const LEFT = { x: 0, y: 0, width: 0.5, height: 1 };
const RIGHT = { x: 0.5, y: 0, width: 0.5, height: 1 };
const LEFT_THIRD = { x: 0, y: 0, width: 1 / 3, height: 1 };
const RIGHT_TWO_THIRDS = { x: 1 / 3, y: 0, width: 2 / 3, height: 1 };
const TOP = { x: 0, y: 0, width: 1, height: 0.5 };
const QUARTER = { x: 0.5, y: 0.5, width: 0.5, height: 0.5 };

// Nothing tiled (the app alone, or over a maximized one): the right half.
assert.strictEqual(sideFor([], 300, 720), "right");
// The other half free: that half.
assert.strictEqual(sideFor([LEFT], 300, 720), "right");
assert.strictEqual(sideFor([RIGHT], 300, 720), "left");
// The divider's 1/3 and 2/3 are halves too.
assert.strictEqual(sideFor([LEFT_THIRD], 300, 720), "right");
assert.strictEqual(sideFor([RIGHT_TWO_THIRDS], 300, 720), "left");
// Both taken: the right half.
assert.strictEqual(sideFor([LEFT, RIGHT], 300, 720), "right");
// Tiles that are not a left or right half (a top half, a quarter) do not take a side.
assert.strictEqual(sideFor([TOP, QUARTER], 300, 720), "right");
// A window wider than a half at its minimum floats (8 px for the split's gaps).
assert.strictEqual(sideFor([], 713, 720), "");
assert.strictEqual(sideFor([], 712, 720), "right");
assert.strictEqual(sideFor([LEFT], 900, 720), "");
// The halves' test.
assert.ok(isLeft(LEFT) && !isRight(LEFT) && isRight(RIGHT) && !isLeft(RIGHT));
assert.ok(!isLeft(TOP) && !isRight(TOP) && !isLeft(null) && !isRight(undefined));
console.log("tablet-snap.test.js: ok");
