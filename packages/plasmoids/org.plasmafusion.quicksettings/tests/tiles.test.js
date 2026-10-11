// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/tiles.js (not installed). Run: node tests/tiles.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "tiles.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { DEFAULT_ORDER, list, same, known, merge, shown, addable, arrange, moveTo, moveBy, slotAt, setHidden, isDefault } = globalThis;

// ---- The settings' lists
assert.deepStrictEqual(list(undefined), [], "no value: an empty list");
assert.deepStrictEqual(list(""), [], "an empty StringList read as an empty string");
assert.deepStrictEqual(list("wifi"), ["wifi"], "one entry read as a string");
assert.deepStrictEqual(list({ length: 2, 0: "dnd", 1: "power" }), ["dnd", "power"], "a sequence (array-like) as an array");
assert.ok(same(["a", "b"], ["a", "b"]) && !same(["a", "b"], ["b", "a"]) && !same(["a"], ["a", "b"]), "same entries in the same order");
assert.deepStrictEqual(known(["wifi", "nosuchtile", "wifi", "dnd"]), ["wifi", "dnd"], "unknown ids and repeats dropped");

// ---- The order: the default for a new user, the user's own kept, new tiles placed
assert.deepStrictEqual(merge([]), DEFAULT_ORDER, "no stored order: the default order");
assert.deepStrictEqual(merge(undefined), DEFAULT_ORDER, "no key at all: the default order");
const custom = ["darkstyle", "wifi", "keepawake", "bluetooth", "nightlight", "dnd", "power", "devices", "hotspot", "chargelimit", "tabletmode"];
assert.deepStrictEqual(merge(custom), custom, "a full stored order is kept as it is");
assert.deepStrictEqual(merge(["power", "wifi", "power", "bogus"]),
                       ["power", "darkstyle", "keepawake", "devices", "hotspot", "chargelimit", "tabletmode", "wifi", "bluetooth", "nightlight", "dnd"],
                       "a partial order: every missing tile after the one before it in the default order, wherever that one is");
// A release adds a tile: the user who customised finds it after its default predecessor, wherever
// that one is now; one first in the default order goes first; two new neighbours stay together.
const next = ["wifi", "airplane", "bluetooth", "nightlight", "dnd", "power", "darkstyle", "keepawake", "devices", "hotspot", "chargelimit", "tabletmode"];
assert.deepStrictEqual(merge(custom, next),
                       ["darkstyle", "wifi", "airplane", "keepawake", "bluetooth", "nightlight", "dnd", "power", "devices", "hotspot", "chargelimit", "tabletmode"],
                       "a new tile after its default predecessor (Airplane after Wi-Fi, which the user moved)");
assert.deepStrictEqual(merge(["dnd", "wifi"], ["focus", "wifi", "dnd"]), ["focus", "dnd", "wifi"], "a new first tile goes first");
assert.deepStrictEqual(merge(["dnd", "wifi"], ["wifi", "mic", "camera", "dnd"]), ["dnd", "wifi", "mic", "camera"], "two new neighbours stay in their order");
assert.deepStrictEqual(merge(["tabletmode", "wifi"], ["wifi", "dnd", "tabletmode"]), ["tabletmode", "wifi", "dnd"], "a new tile follows its predecessor, not the end");

// ---- The grid: hidden tiles never, conditional ones only when they apply
const conditions = { devices: false, hotspot: true, chargelimit: false, tabletmode: false };
assert.deepStrictEqual(shown(DEFAULT_ORDER, [], conditions),
                       ["wifi", "bluetooth", "nightlight", "dnd", "power", "darkstyle", "keepawake", "hotspot"],
                       "the seven tiles and the conditional ones that apply");
assert.deepStrictEqual(shown(DEFAULT_ORDER, ["nightlight", "devices"], { devices: true }),
                       ["wifi", "bluetooth", "dnd", "power", "darkstyle", "keepawake", "hotspot", "chargelimit", "tabletmode"],
                       "a hidden tile is left out, also a hidden conditional one whose condition holds");
assert.deepStrictEqual(shown(DEFAULT_ORDER, [], null), DEFAULT_ORDER, "no conditions: every tile applies");
assert.deepStrictEqual(addable(DEFAULT_ORDER, ["devices", "nightlight", "chargelimit"], conditions), ["nightlight"],
                       "the tray: hidden tiles that could show now; a hidden one that does not apply waits");
assert.deepStrictEqual(addable(DEFAULT_ORDER, ["devices", "nightlight"], { devices: true }), ["nightlight", "devices"],
                       "the tray in the grid's order");

// ---- Reordering the shown tiles keeps the others' places
const before = shown(DEFAULT_ORDER, ["nightlight"], conditions);
const moved = moveTo(before, "hotspot", 0);
assert.deepStrictEqual(moved, ["hotspot", "wifi", "bluetooth", "dnd", "power", "darkstyle", "keepawake"], "a shown tile moved first");
assert.deepStrictEqual(arrange(DEFAULT_ORDER, before, moved),
                       ["hotspot", "wifi", "nightlight", "bluetooth", "dnd", "power", "darkstyle", "devices", "keepawake", "chargelimit", "tabletmode"],
                       "the full order: the shown tiles take their places in the new order, hidden and absent ones keep theirs");
assert.deepStrictEqual(shown(arrange(DEFAULT_ORDER, before, moved), ["nightlight"], conditions), moved, "the grid shows the new order");
assert.deepStrictEqual(moveBy(["a", "b", "c", "d"], "b", 1), ["a", "c", "b", "d"], "one place later");
assert.deepStrictEqual(moveBy(["a", "b", "c", "d"], "b", -1), ["b", "a", "c", "d"], "one place earlier");
assert.deepStrictEqual(moveBy(["a", "b", "c", "d"], "a", 2), ["b", "c", "a", "d"], "a row down in two columns");
assert.deepStrictEqual(moveBy(["a", "b", "c", "d"], "a", -2), ["a", "b", "c", "d"], "clamped at the start");
assert.deepStrictEqual(moveBy(["a", "b", "c", "d"], "c", 9), ["a", "b", "d", "c"], "clamped at the end");
assert.deepStrictEqual(moveBy(["a", "b"], "x", 1), ["a", "b"], "an id not in the list: unchanged");

// ---- Where a dragged tile lands: two columns of 157 x 60 with 10 px gaps
const slot = (x, y) => slotAt(x, y, 9, 2, 157, 60, 10, 10);
assert.strictEqual(slot(78, 30), 0, "first cell");
assert.strictEqual(slot(240, 30), 1, "second column");
assert.strictEqual(slot(78, 100), 2, "second row");
assert.strictEqual(slot(240, 245), 7, "fourth row, second column");
assert.strictEqual(slot(240, 400), 8, "below the last row: the last slot");
assert.strictEqual(slot(-50, -50), 0, "above and left of the grid: the first slot");
assert.strictEqual(slot(900, 30), 1, "right of the grid: the last column");
assert.strictEqual(slotAt(10, 10, 0, 2, 157, 60, 10, 10), -1, "no tiles: no slot");

// ---- Hide, show again, reset
assert.deepStrictEqual(setHidden([], "dnd", true), ["dnd"], "hide");
assert.deepStrictEqual(setHidden(["dnd"], "dnd", true), ["dnd"], "hide twice: once in the list");
assert.deepStrictEqual(setHidden(["dnd", "power"], "dnd", false), ["power"], "show again");
assert.ok(isDefault([], []) && isDefault(DEFAULT_ORDER, []) && isDefault(undefined, ["bogus"]), "the defaults");
assert.ok(!isDefault(custom, []) && !isDefault([], ["dnd"]), "a custom order or a hidden tile is not the default");
console.log("tiles: all checks passed");
