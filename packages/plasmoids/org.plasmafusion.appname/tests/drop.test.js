// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of target() and flick() in contents/code/drop.js (not installed): the window pill's drag
// in tablet posture (board TabletSnap.dc.html). Run: node tests/drop.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");
const file = path.join(__dirname, "..", "contents", "code", "drop.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { target, flick } = globalThis;
assert.strictEqual(typeof target, "function", "drop.js does not define target");

// The ThinkPad in tablet posture (1440 x 900 logical): the work area from below the 44 px top bar
// to above the dock's 20 px strip.
const at = (x, y) => target({ x, y }, 1440, 44, 880);
// Back in the top bar: nothing.
assert.strictEqual(at(60, 20), "");
assert.strictEqual(at(700, 43), "");
// The outer thirds split, the middle third is full screen (the board's finger at 250, 660: left).
assert.strictEqual(at(250, 660), "left");
assert.strictEqual(at(479, 300), "left");
assert.strictEqual(at(481, 300), "full");
assert.strictEqual(at(720, 44), "full");
assert.strictEqual(at(959, 500), "full");
assert.strictEqual(at(961, 500), "right");
assert.strictEqual(at(1430, 700), "right");
// The bottom 96 px of the work area: home, whatever the side.
assert.strictEqual(at(720, 784), "home");
assert.strictEqual(at(100, 879), "home");
assert.strictEqual(at(1400, 783), "right");
// A portrait screen (900 x 1440): thirds of its width.
assert.strictEqual(target({ x: 290, y: 700 }, 900, 44, 1420), "left");
assert.strictEqual(target({ x: 450, y: 700 }, 900, 44, 1420), "full");
assert.strictEqual(target({ x: 610, y: 700 }, 900, 44, 1420), "right");

// Flicks: 800 px/s or faster sideways, more sideways than down.
assert.strictEqual(flick(800, 0), "right");
assert.strictEqual(flick(-1500, 200), "left");
assert.strictEqual(flick(799, 0), "");
assert.strictEqual(flick(1000, 1200), "");
assert.strictEqual(flick(0, 2000), "");
// The window's screen against the bar's: only the same screen.
const { sameScreen } = globalThis;
const laptop = { x: 0, y: 0, width: 1440, height: 900 };
assert.ok(sameScreen({ x: 0, y: 0, width: 1440, height: 900 }, laptop));
assert.ok(!sameScreen({ x: 1440, y: 0, width: 1920, height: 1080 }, laptop));
assert.ok(!sameScreen({ x: 0, y: 0, width: 1920, height: 1080 }, laptop));
assert.ok(!sameScreen(null, laptop));
assert.ok(!sameScreen(undefined, laptop) && !sameScreen(laptop, null));
console.log("drop.test.js: ok");
