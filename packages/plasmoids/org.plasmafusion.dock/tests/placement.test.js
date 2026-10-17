// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/placement.js (not installed): where the name pill and the window previews
// go for each edge of the dock (board DockPosition.dc.html). Run: node tests/placement.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "placement.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { edgeOf, popupPosition } = globalThis;

// Plasma's locations (Plasma::Types): 3 left, 4 right; the dock is at the bottom otherwise.
assert.deepStrictEqual([edgeOf(3, 3, 4), edgeOf(4, 3, 4), edgeOf(2, 3, 4), edgeOf(undefined, 3, 4)], ["left", "right", "bottom", "bottom"]);

const pill = { width: 80, height: 28 };
// The bottom dock: centred over the anchor, its bottom on the anchor's top (as before).
assert.deepStrictEqual(popupPosition({ x: 600, y: 800, width: 62, height: 1 }, pill, "bottom", null), { x: 591, y: 772 });
// On the left: beside the anchor (12 px off the icon, placed by the dock), centred on its height.
assert.deepStrictEqual(popupPosition({ x: 102, y: 300, width: 0, height: 62 }, pill, "left", null), { x: 102, y: 317 });
// On the right: its right edge on the anchor.
assert.deepStrictEqual(popupPosition({ x: 1338, y: 300, width: 0, height: 62 }, pill, "right", null), { x: 1258, y: 317 });

// A preview kept 8 px inside the screen along the dock: across the bottom, up and down on a side.
const screen = { x: 0, y: 0, width: 1440, height: 900 };
const preview = { width: 400, height: 200 };
assert.strictEqual(popupPosition({ x: 20, y: 800, width: 48, height: 1 }, preview, "bottom", screen).x, 8);
assert.strictEqual(popupPosition({ x: 1400, y: 800, width: 48, height: 1 }, preview, "bottom", screen).x, 1032);
assert.strictEqual(popupPosition({ x: 102, y: 20, width: 0, height: 48 }, preview, "left", screen).y, 8);
assert.strictEqual(popupPosition({ x: 102, y: 860, width: 0, height: 48 }, preview, "left", screen).y, 692);
assert.strictEqual(popupPosition({ x: 1338, y: 860, width: 0, height: 48 }, preview, "right", screen).y, 692);
// No screen known: not clamped.
assert.strictEqual(popupPosition({ x: 102, y: 860, width: 0, height: 48 }, preview, "left", { x: 0, y: 0, width: 0, height: 0 }).y, 784);

console.log("placement: all checks passed");
