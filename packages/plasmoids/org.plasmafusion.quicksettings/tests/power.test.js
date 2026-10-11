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
const { options, toggleTarget, holds } = globalThis;

const all = ["performance", "balanced", "power-saver"];
const rows = (list, active, reason) => options(list, active, reason).map(o => o.profile + (o.active ? "*" : "") + (o.enabled ? "" : "-"));
assert.deepStrictEqual(rows(all, "balanced", ""), ["power-saver", "balanced*", "performance"], "the daemon's profiles in order, the active one marked");
assert.deepStrictEqual(rows(all, "balanced", "lap-detected"), ["power-saver", "balanced*", "performance-"], "inhibited: Performance listed but not choosable");
assert.deepStrictEqual(rows(all, "performance", "high-operating-temperature"), ["power-saver", "balanced", "performance*"],
                       "inhibited while active: Performance stays the chosen row");
assert.deepStrictEqual(rows(["balanced", "power-saver"], "power-saver", ""), ["power-saver*", "balanced"], "only the offered profiles");
assert.deepStrictEqual(options(undefined, "", ""), [], "no daemon profiles: no rows");

// The tile's body: never through Performance on the way from Balanced to Power saver (P7).
assert.strictEqual(toggleTarget(all, "balanced", "", ""), "power-saver", "balanced -> power saver by default");
assert.strictEqual(toggleTarget(all, "power-saver", "", ""), "balanced", "power saver -> balanced");
assert.strictEqual(toggleTarget(all, "performance", "", "performance"), "balanced", "performance -> balanced");
assert.strictEqual(toggleTarget(all, "balanced", "", "performance"), "performance", "balanced -> the last other profile chosen");
assert.strictEqual(toggleTarget(all, "balanced", "lap-detected", "performance"), "power-saver", "inhibited: the last profile Performance falls back to power saver");
assert.strictEqual(toggleTarget(["balanced", "performance"], "balanced", "", "power-saver"), "performance", "no power saver offered: performance");
assert.strictEqual(toggleTarget(["balanced", "performance"], "balanced", "lap-detected", ""), "", "only an inhibited Performance: nothing");
assert.strictEqual(toggleTarget(["balanced"], "balanced", "", ""), "", "one profile: nothing to switch to");
assert.strictEqual(toggleTarget(["power-saver", "performance"], "power-saver", "", ""), "", "no balanced offered: nothing to go back to");
assert.strictEqual(toggleTarget([], "", "", ""), "", "no daemon profiles");
assert.deepStrictEqual(holds([{ Name: "Steam", ApplicationId: "com.valvesoftware.Steam", Profile: "performance", Reason: "game" },
                              { Name: "", ApplicationId: "org.example.tool", Profile: "power-saver" },
                              { Name: "", ApplicationId: "", Profile: "balanced" }]),
                       [{ name: "Steam", profile: "performance" }, { name: "org.example.tool", profile: "power-saver" }],
                       "holds by name, else application id; nameless ones dropped");
assert.deepStrictEqual(holds(undefined), [], "no holds");
console.log("power: all checks passed");
