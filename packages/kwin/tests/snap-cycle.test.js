// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the snap script's contents/ui/Cycle.js (snap sizes from the keyboard).
// Run: node packages/kwin/tests/snap-cycle.test.js (80-kwin.sh runs it).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "scripts", "plasmafusion-snap", "contents", "ui", "Cycle.js");
vm.runInThisContext(fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (l) => " ".repeat(l.length)), { filename: pathToFileURL(file).href });
const { stepOf, nextStep, neighbourOf, stepWidths, currentStep } = globalThis;

// A 1440 x 900 screen with a 34 px top bar.
const area = { x: 0, y: 34, width: 1440, height: 866 };
const r = (x, w) => ({ x: x, y: 34, width: w, height: 866 });

// ---- where a window is
assert.strictEqual(stepOf(r(0, 720), area, "left"), "half", "the left half");
assert.strictEqual(stepOf(r(0, 480), area, "left"), "third", "the left third");
assert.strictEqual(stepOf(r(0, 960), area, "left"), "twoThirds", "the left two thirds");
assert.strictEqual(stepOf(r(720, 720), area, "right"), "half", "the right half");
assert.strictEqual(stepOf(r(960, 480), area, "right"), "third", "the right third");
assert.strictEqual(stepOf(r(480, 960), area, "right"), "twoThirds", "the right two thirds");
assert.strictEqual(stepOf(r(0, 712), area, "left"), "half", "a terminal a few pixels narrower (character cells)");
assert.strictEqual(stepOf(r(0, 720), area, "right"), "", "the left half is no step on the right");
assert.strictEqual(stepOf(r(40, 720), area, "left"), "", "away from the edge: no step");
assert.strictEqual(stepOf({ x: 0, y: 34, width: 720, height: 433 }, area, "left"), "", "a quarter is no step");
assert.strictEqual(stepOf(r(0, 600), area, "left"), "", "another width: no step");
assert.strictEqual(stepOf(r(0, 1440), area, "left"), "", "maximized: no step");
// A second screen to the right of the first: its own area.
const area2 = { x: 1440, y: 0, width: 1920, height: 1080 };
assert.strictEqual(stepOf({ x: 1440, y: 0, width: 640, height: 1080 }, area2, "left"), "third", "a third on a second screen");
// The widths as the script places them, with the gap (6 px).
assert.deepStrictEqual(stepWidths(1440, 6, 6), { half: 717, third: 476, twoThirds: 957 }, "the widths with a 6 px gap");
assert.strictEqual(stepOf(r(0, 476), area, "left", 6, 6), "third", "the third the script made with the gap");
assert.strictEqual(stepOf(r(0, 957), area, "left", 6, 6), "twoThirds", "the two thirds with the gap");
// The largest gap on a small area: the third is far from a third of the width.
const small = { x: 0, y: 34, width: 1024, height: 700 };
const w48 = stepWidths(1024, 48, 48);
assert.strictEqual(stepOf({ x: 0, y: 34, width: Math.round(w48.third), height: 700 }, small, "left", 48, 48), "third",
                   "a 48 px gap on a 1024 px area: its third (" + Math.round(w48.third) + " px) is a third");
assert.strictEqual(stepOf({ x: 0, y: 34, width: Math.round(w48.twoThirds), height: 700 }, small, "left", 48, 48), "twoThirds",
                   "  and its two thirds");
// Not at the top of the area: not snapped.
assert.strictEqual(stepOf({ x: 0, y: 100, width: 720, height: 800 }, area, "left"), "", "a half-width window lower down is no step");
assert.strictEqual(stepOf({ x: 0, y: 34, width: 720, height: 840 }, area, "left"), "half", "a terminal's bottom a few rows short still is");

// ---- a step asked for but not drawn yet
const asked = { side: "left", step: "third", at: 1000 };
assert.strictEqual(currentStep("half", asked, "left", 1400), "third", "the client still shows the half: the third asked counts");
assert.strictEqual(currentStep("third", asked, "left", 1400), "third", "drawn: the same");
assert.strictEqual(currentStep("half", asked, "left", 2500), "half", "a second later the size decides");
assert.strictEqual(currentStep("half", asked, "right", 1400), "half", "another side: the size decides");
assert.strictEqual(currentStep("", null, "left", 1400), "", "nothing asked");

// ---- the cycle
assert.strictEqual(nextStep("", false), "half", "not on that side yet: the half");
assert.strictEqual(nextStep("half", false), "third");
assert.strictEqual(nextStep("third", false), "twoThirds");
assert.strictEqual(nextStep("twoThirds", false), "half", "one screen: back to the half");
assert.strictEqual(nextStep("twoThirds", true), "screen", "a screen on that side: there");
assert.strictEqual(nextStep("half", true), "third", "the sizes first, then the screen");

// ---- the neighbouring screen
const left = { x: 0, y: 0, width: 1440, height: 900 };
const right = { x: 1440, y: 0, width: 1920, height: 1080 };
const above = { x: 1440, y: -1080, width: 1920, height: 1080 };
assert.strictEqual(neighbourOf([left, right, above], right, "left"), 0, "the screen to the left");
assert.strictEqual(neighbourOf([left, right, above], left, "right"), 1, "the screen to the right");
assert.strictEqual(neighbourOf([left, right, above], left, "left"), -1, "none on that side");
assert.strictEqual(neighbourOf([left, right, above], right, "right"), -1, "a screen above is not to the right");
const below = { x: 3360, y: 1080, width: 1280, height: 1024 };
assert.strictEqual(neighbourOf([left, right, below], right, "right"), -1, "a screen to the right but wholly below shares no height");
const far = { x: 3360, y: 0, width: 1280, height: 1024 };
assert.strictEqual(neighbourOf([far, left, right], left, "right"), 2, "the nearest one");
console.log("snap-cycle.test.js: all passed");
