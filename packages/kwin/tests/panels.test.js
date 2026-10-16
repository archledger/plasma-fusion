// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the snap script's contents/ui/Panels.js (what ensure-topbars.js made, for the power
// tier, and whether to ask it again). Run: node packages/kwin/tests/panels.test.js (80-kwin.sh runs it).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "scripts", "plasmafusion-snap", "contents", "ui", "Panels.js");
vm.runInThisContext(fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (l) => " ".repeat(l.length)), { filename: pathToFileURL(file).href });
const { addedWidgets, needsRetry, afterAnswer } = globalThis;

const both = (bars, docks) => "top bars: screens 2, " + bars + "\ndocks: " + docks;
assert.strictEqual(addedWidgets(both("added 1, completed 0", "one (plasmafusionrc [Dock] EveryScreen is not true)")), true, "a top bar made");
assert.strictEqual(addedWidgets(both("added 0, completed 1", "one (plasmafusionrc [Dock] EveryScreen is not true)")), true, "a top bar completed");
assert.strictEqual(addedWidgets(both("added 0, completed 0", "screens 2, added 1")), true, "a dock made (a screen plugged in)");
assert.strictEqual(addedWidgets(both("added 0, completed 0", "screens 2, added 1, not made 1")), true, "one made, one not");
assert.strictEqual(addedWidgets(both("added 0, completed 0", "screens 2, added 0")), false, "nothing new");
assert.strictEqual(addedWidgets(both("added 0, completed 0", "screens 2, added 0, not made 1")), false, "none made");
assert.strictEqual(addedWidgets("top bars: skipped, the layout is not loaded yet"), false, "skipped");
assert.strictEqual(addedWidgets(""), false, "no answer");
// Asked again while plasmashell has not loaded its layout: either part says so.
assert.strictEqual(needsRetry("top bars: skipped, the layout is not loaded yet\ndocks: skipped, the layout is not loaded yet"), true, "both skipped");
assert.strictEqual(needsRetry("top bars: off (plasmafusionrc [TopBar] EveryScreen=false)\ndocks: skipped, the layout is not loaded yet"), true,
                   "top bars off, the docks skipped (Dock on every screen alone)");
assert.strictEqual(needsRetry(both("added 0, completed 0", "screens 2, added 0")), false, "an answer");
assert.strictEqual(needsRetry(""), false, "no answer (the call failing is handled apart)");
// Both at once: the top bars' part skipped (a top panel of an unplugged screen) while the docks'
// part made a dock. The new dock gets the tier now, and the top bars are asked again.
assert.deepStrictEqual(afterAnswer("top bars: skipped, 1 top panel(s) without a screen\ndocks: screens 2, added 1"),
                       { powerTier: true, retry: true }, "a dock made while the top bars' part was skipped");
assert.deepStrictEqual(afterAnswer(both("added 0, completed 0", "screens 2, added 0")), { powerTier: false, retry: false }, "nothing to do");
assert.deepStrictEqual(afterAnswer("top bars: skipped, the layout is not loaded yet\ndocks: skipped, the layout is not loaded yet"),
                       { powerTier: false, retry: true }, "only ask again");
console.log("panels.test.js: all passed");
