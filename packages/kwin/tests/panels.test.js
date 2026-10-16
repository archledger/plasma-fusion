// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the snap script's contents/ui/Panels.js (what ensure-topbars.js made, for the power
// tier). Run: node packages/kwin/tests/panels.test.js (80-kwin.sh runs it).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "scripts", "plasmafusion-snap", "contents", "ui", "Panels.js");
vm.runInThisContext(fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (l) => " ".repeat(l.length)), { filename: pathToFileURL(file).href });
const { addedWidgets } = globalThis;

const both = (bars, docks) => "top bars: screens 2, " + bars + "\ndocks: " + docks;
assert.strictEqual(addedWidgets(both("added 1, completed 0", "one (plasmafusionrc [Dock] EveryScreen is not true)")), true, "a top bar made");
assert.strictEqual(addedWidgets(both("added 0, completed 1", "one (plasmafusionrc [Dock] EveryScreen is not true)")), true, "a top bar completed");
assert.strictEqual(addedWidgets(both("added 0, completed 0", "screens 2, added 1")), true, "a dock made (a screen plugged in)");
assert.strictEqual(addedWidgets(both("added 0, completed 0", "screens 2, added 1, not made 1")), true, "one made, one not");
assert.strictEqual(addedWidgets(both("added 0, completed 0", "screens 2, added 0")), false, "nothing new");
assert.strictEqual(addedWidgets(both("added 0, completed 0", "screens 2, added 0, not made 1")), false, "none made");
assert.strictEqual(addedWidgets("top bars: skipped, the layout is not loaded yet"), false, "skipped");
assert.strictEqual(addedWidgets(""), false, "no answer");
console.log("panels.test.js: all passed");
