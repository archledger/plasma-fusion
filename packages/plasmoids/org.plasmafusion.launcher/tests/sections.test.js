// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the launcher's chip sections in contents/code/launcher.js (not installed): the Recent
// and Places chips turned off by showRecentApps and showPlaces (the Plasma Fusion settings page or
// the launcher's own). Run: node tests/sections.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "launcher.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { shownFixedChips } = globalThis;
assert.strictEqual(typeof shownFixedChips, "function", "launcher.js does not define shownFixedChips");

const all = { key: "all", label: "All", row: -1, view: "home" };
const recent = { key: "recentapps", label: "Recent", row: -1, view: "history" };
const places = { key: "places", label: "Places", row: -1, view: "places" };
const fixed = [all, recent, places];
const keys = (chips) => chips.map((c) => c.key);

assert.deepStrictEqual(keys(shownFixedChips(fixed, true, true)), ["all", "recentapps", "places"], "both on: the three chips");
assert.deepStrictEqual(keys(shownFixedChips(fixed, false, true)), ["all", "places"], "Recent off");
assert.deepStrictEqual(keys(shownFixedChips(fixed, true, false)), ["all", "recentapps"], "Places off");
assert.deepStrictEqual(keys(shownFixedChips(fixed, false, false)), ["all"], "both off: All stays");
assert.deepStrictEqual(shownFixedChips(fixed, false, true)[1], places, "the chips themselves are kept as they are");
assert.deepStrictEqual(keys(fixed), ["all", "recentapps", "places"], "the list given is not changed");
console.log("sections.test.js: all passed");
