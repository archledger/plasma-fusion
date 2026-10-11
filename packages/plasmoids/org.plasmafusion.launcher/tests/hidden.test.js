// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the settings page's hidden-app merge in contents/code/launcher.js (not installed).
// Run: node tests/hidden.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "launcher.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { withoutUnhidden } = globalThis;
assert.strictEqual(typeof withoutUnhidden, "function", "launcher.js does not define withoutUnhidden");

const hidden = ["org.kde.kcalc.desktop", "org.kde.kwrite.desktop", "gone.desktop"];
assert.deepStrictEqual(withoutUnhidden(hidden, []), hidden, "nothing shown again: the list as it is");
assert.deepStrictEqual(withoutUnhidden(hidden, ["org.kde.kwrite.desktop"]), ["org.kde.kcalc.desktop", "gone.desktop"],
                       "one app shown again, the order kept");
assert.deepStrictEqual(withoutUnhidden(hidden, hidden), [], "Show All");
assert.deepStrictEqual(withoutUnhidden(undefined, ["x"]), [], "no list yet");
assert.deepStrictEqual(withoutUnhidden(["a.desktop", "", "b.desktop"], null), ["a.desktop", "b.desktop"], "empty entries dropped");
// Apply while the launcher hid another app meanwhile (the live list gained it): that app stays
// hidden, the one the page showed again does not come back.
const live = hidden.concat(["org.kde.elisa.desktop"]);
assert.deepStrictEqual(withoutUnhidden(live, ["org.kde.kcalc.desktop"]),
                       ["org.kde.kwrite.desktop", "gone.desktop", "org.kde.elisa.desktop"], "merged with the live list");
// QML string lists arrive as array-like objects.
assert.deepStrictEqual(withoutUnhidden({ length: 2, 0: "a.desktop", 1: "b.desktop" }, ["b.desktop"]), ["a.desktop"], "array-like");
console.log("hidden: ok");
