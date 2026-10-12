// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/shared.js (not installed). Run: node tests/shared.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "shared.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { adoptFrom } = globalThis;

assert.strictEqual(adoptFrom(5, [], -1), -1, "the first widget: nobody to take them from");
assert.strictEqual(adoptFrom(0, [0], 0), 0, "before 0.5.0 (no revisions): the leader's, as before");
assert.strictEqual(adoptFrom(0, [0, 0], 1), 1, "equal revisions: the leader's, wherever it came");
// After a restart the external screen's bar, away while the user edited the tiles, loads first.
assert.strictEqual(adoptFrom(2000, [1000], 0), -1, "the main bar joins with newer settings: it keeps them and gives them on");
assert.strictEqual(adoptFrom(1000, [2000], 0), 0, "the stale bar joins second: it takes the newer ones");
assert.strictEqual(adoptFrom(1500, [1000, 2000], 0), 1, "the newest of those there, not the leader's");
assert.strictEqual(adoptFrom(2000, [2000], 0), 0, "the same revision: taken (nothing to give)");
assert.strictEqual(adoptFrom(1000, ["2000"], 0), 0, "revisions read back as text compare as numbers");
console.log("shared: all checks passed");
