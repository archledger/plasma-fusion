// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the tablet script's contents/ui/Requests.js (the right-edge swipe's quick settings
// request). Run: node packages/kwin/tests/tablet-requests.test.js (81-kwin-tablet.sh runs it).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "scripts", "plasmafusion-tablet", "contents", "ui", "Requests.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { swipeOutput, openRequest } = globalThis;

const internal = (s) => s.name.startsWith("eDP");
const laptop = { name: "eDP-1" }, monitor = { name: "DP-2" };
assert.strictEqual(swipeOutput([monitor, laptop], internal, monitor), "eDP-1", "the touch screen, not the active monitor");
assert.strictEqual(swipeOutput([monitor], internal, monitor), "DP-2", "no built-in screen: the active one");
assert.strictEqual(swipeOutput([], internal, null), "", "nothing known");
assert.strictEqual(openRequest("sheet", 17, "eDP-1"), "sheet:17:eDP-1");
assert.strictEqual(openRequest("sheet", 17, ""), "sheet:17", "without an output, the old form");
// Quick settings reads the output back from the same text.
const qs = path.join(__dirname, "..", "..", "plasmoids", "org.plasmafusion.quicksettings", "contents", "code", "requests.js");
vm.runInThisContext(fs.readFileSync(qs, "utf8").replace(/^\.pragma library$/m, (l) => " ".repeat(l.length)), { filename: pathToFileURL(qs).href });
assert.deepStrictEqual(globalThis.parse(openRequest("sheet", 17, "eDP-1")), { mode: "sheet", output: "eDP-1" });
console.log("tablet-requests.test.js: ok");
