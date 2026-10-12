// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/requests.js (not installed). Run: node tests/requests.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "requests.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { parse, acts, decide } = globalThis;

assert.deepStrictEqual(parse("sheet:1760000000000:eDP-1"), { mode: "sheet", output: "eDP-1" });
assert.deepStrictEqual(parse("clipboard:1760000000000"), { mode: "clipboard", output: "" });
assert.deepStrictEqual(parse("notifications 1760000000000"), { mode: "notifications", output: "" });
assert.deepStrictEqual(parse("sheet:1:DP-1:2"), { mode: "sheet", output: "DP-1:2" }, "an output name with a colon");
assert.strictEqual(parse("").mode, "", "no request");
assert.strictEqual(parse(undefined).mode, "");

// An output named: the widget on it acts, the others do not.
assert.strictEqual(acts("eDP-1", "eDP-1", false), true);
assert.strictEqual(acts("eDP-1", "DP-1", true), false, "the leader on another output does not act");
assert.strictEqual(acts("eDP-1", "", false), true, "a widget that does not know its output yet acts");
// No output known (KWin did not answer): only the leader, one sheet, not one per screen.
assert.strictEqual(acts("", "eDP-1", true), true);
assert.strictEqual(acts("", "DP-1", false), false);
// A widget whose output name is still the window's guess waits for the name before it decides on a
// request that names an output; once it is known, or the wait is over, it decides as acts() does.
assert.strictEqual(typeof decide, "function", "requests.js does not define decide");
assert.strictEqual(decide("DP-1", "eDP-1", false, true, false), "wait", "the guess names another screen: wait");
assert.strictEqual(decide("eDP-1", "eDP-1", false, false, false), "wait", "the guess names this one: wait as well");
assert.strictEqual(decide("DP-1", "DP-1", true, false, false), "act", "the name known: the widget on that output acts");
assert.strictEqual(decide("DP-1", "eDP-1", true, true, false), "skip", "the name known, another output: skip");
assert.strictEqual(decide("DP-1", "eDP-1", false, true, true), "skip", "the wait over: the guess decides");
assert.strictEqual(decide("eDP-1", "eDP-1", false, false, true), "act");
assert.strictEqual(decide("", "eDP-1", false, true, false), "act", "no output named: the leader, at once");
assert.strictEqual(decide("", "eDP-1", false, false, false), "skip");
console.log("requests.test.js: ok");
