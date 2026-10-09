// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/power.js (not installed). Run: node tests/power.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "power.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { next, choices, holds } = globalThis;

const all = ["performance", "balanced", "power-saver"];
assert.deepStrictEqual(choices(all, "balanced", ""), ["power-saver", "balanced", "performance"], "the daemon's profiles in order");
assert.strictEqual(next(all, "balanced", ""), "performance", "balanced -> performance");
assert.strictEqual(next(all, "performance", ""), "power-saver", "performance -> power-saver (wraps)");
assert.strictEqual(next(all, "balanced", "lap-detected"), "power-saver", "inhibited: Performance is skipped");
assert.strictEqual(next(all, "power-saver", "high-operating-temperature"), "balanced", "inhibited: power-saver -> balanced");
assert.strictEqual(next(all, "performance", "lap-detected"), "power-saver", "inhibited while active: the cycle leaves Performance");
assert.strictEqual(next(["balanced", "power-saver"], "power-saver", ""), "balanced", "no Performance offered");
assert.strictEqual(next(["balanced"], "balanced", ""), "", "one profile: nothing to switch to");
assert.strictEqual(next([], "", ""), "", "no daemon profiles");
assert.deepStrictEqual(holds([{ Name: "Steam", ApplicationId: "com.valvesoftware.Steam", Profile: "performance", Reason: "game" },
                              { Name: "", ApplicationId: "org.example.tool", Profile: "power-saver" },
                              { Name: "", ApplicationId: "", Profile: "balanced" }]),
                       [{ name: "Steam", profile: "performance" }, { name: "org.example.tool", profile: "power-saver" }],
                       "holds by name, else application id; nameless ones dropped");
assert.deepStrictEqual(holds(undefined), [], "no holds");
console.log("power: all checks passed");
