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
const { edgeOf, popupPosition, room, along, taskAt, awayFromEdge } = globalThis;

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
// Beside a dock on a side, kept inside the screen across it too: a preview wider than the room
// beside the dock lies over the dock, 8 px from the screen's edge.
const wide = { width: 1378, height: 200 };
assert.strictEqual(popupPosition({ x: 104, y: 400, width: 0, height: 48 }, wide, "left", screen).x, 54);
assert.strictEqual(popupPosition({ x: 1336, y: 400, width: 0, height: 48 }, wide, "right", screen).x, 8);
// The room for a preview: the screen less 16 px at the bottom; beside a side dock, from the
// anchor to 8 px from the screen's far edge.
assert.deepStrictEqual([room({ x: 600, y: 800, width: 62, height: 1 }, "bottom", screen),
                        room({ x: 104, y: 400, width: 0, height: 48 }, "left", screen),
                        room({ x: 1336, y: 400, width: 0, height: 48 }, "right", screen)], [1424, 1328, 1328]);
assert.strictEqual(room({ x: 1544, y: 400, width: 0, height: 48 }, "left", { x: 1440, y: 0, width: 1280, height: 800 }), 1168);
// No screen known: not clamped.
assert.strictEqual(popupPosition({ x: 102, y: 860, width: 0, height: 48 }, preview, "left", { x: 0, y: 0, width: 0, height: 0 }).y, 784);

// A point along the row: y on a side, x at the bottom; the task under it (a file dropped on it).
assert.deepStrictEqual([along({ x: 30, y: 250 }, "left"), along({ x: 30, y: 250 }, "right"), along({ x: 30, y: 250 }, "bottom")], [250, 250, 30]);
const taskX = [0, 56, 112, 168];
const taskW = [48, 48, 48, 48];
assert.strictEqual(taskAt(along({ x: 30, y: 130 }, "left"), taskX, taskW, [true, true, true, true]), 2);
assert.strictEqual(taskAt(130, taskX, taskW, [true, true, false, true]), -1);
assert.strictEqual(taskAt(52, taskX, taskW, [true, true, true, true]), -1);
assert.strictEqual(taskAt(500, taskX, taskW, [true, true, true, true]), -1);
// The launcher drag only away from the edge.
assert.deepStrictEqual([awayFromEdge({ x: 50, y: 0 }, "left"), awayFromEdge({ x: -50, y: 0 }, "left"),
                        awayFromEdge({ x: -50, y: 0 }, "right"), awayFromEdge({ x: 50, y: 0 }, "right"),
                        awayFromEdge({ x: 0, y: -50 }, "bottom"), awayFromEdge({ x: 0, y: 50 }, "bottom")],
                       [true, false, true, false, true, false]);

console.log("placement: all checks passed");
