// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/tray.js (not installed). Run: node tests/tray.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "tray.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { wanted, shownItems, same, VAULT, PRINTERS, DISPLAY, INPUT_METHOD } = globalThis;

const items = (...active) => [VAULT, PRINTERS, DISPLAY, INPUT_METHOD, "org.kde.plasma.battery"]
    .map(id => ({ id: id, active: active.indexOf(id) !== -1 }));
assert.deepStrictEqual(wanted(items(), 1, false), [], "all passive, one screen: nothing shown");
assert.deepStrictEqual(wanted(items(VAULT), 1, false), [VAULT], "an open vault");
assert.deepStrictEqual(wanted(items(PRINTERS), 1, false), [PRINTERS], "queued print jobs");
assert.deepStrictEqual(wanted(items(DISPLAY), 1, false), [DISPLAY], "presentation mode");
assert.deepStrictEqual(wanted(items(), 2, false), [DISPLAY], "a second screen: display configuration");
assert.deepStrictEqual(wanted(items(INPUT_METHOD), 1, false), [INPUT_METHOD], "the input-method switch while active");
assert.deepStrictEqual(wanted(items(INPUT_METHOD), 1, true), [], "not in tablet posture, where the sheet has the keyboard button");
assert.deepStrictEqual(wanted(items("org.kde.plasma.battery"), 1, false), [], "only the managed items");
assert.deepStrictEqual(wanted(items(VAULT, PRINTERS), 2, false), [VAULT, PRINTERS, DISPLAY], "several at once");
assert.deepStrictEqual(wanted(undefined, 1, false), [], "no tray items yet");

const hidden = [VAULT, "org.kde.plasma.devicenotifier", DISPLAY, PRINTERS, INPUT_METHOD, "org.kde.plasma.volume"];
assert.deepStrictEqual(shownItems([], hidden, [VAULT]), [VAULT], "shown while wanted");
assert.deepStrictEqual(shownItems([VAULT], hidden, []), [], "and taken out again");
assert.deepStrictEqual(shownItems(["org.example.app", VAULT], hidden, [PRINTERS]), ["org.example.app", PRINTERS],
                       "the user's own entries stay, in their order");
assert.deepStrictEqual(shownItems([VAULT], [DISPLAY], []), [VAULT], "an id the user took out of the hidden list is the user's: left shown");
assert.deepStrictEqual(shownItems([], [DISPLAY], [VAULT]), [], "and not shown by this widget either");
assert.deepStrictEqual(shownItems([VAULT, VAULT], hidden, [VAULT]), [VAULT, VAULT], "an entry already there is not added twice");
assert.ok(same(shownItems([PRINTERS], hidden, [PRINTERS]), [PRINTERS]), "nothing to change: the same list (no write)");
assert.ok(!same([VAULT], [PRINTERS]) && !same([], [VAULT]), "same() compares entries and length");
console.log("tray: all checks passed");
