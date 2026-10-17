// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of besideDock() in contents/code/launcher.js (not installed): the card beside a dock on the
// left or right (board DockPosition.dc.html). Run: node tests/beside.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");
const file = path.join(__dirname, "..", "contents", "code", "launcher.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { besideDock } = globalThis;
assert.strictEqual(typeof besideDock, "function", "launcher.js does not define besideDock");

// 1440 x 900 with the 34 px top bar: the card stays in 42..892; the card 680 x 700.
const area = { top: 42, bottom: 892 };
const card = { width: 680, height: 700 };
// The board's dark desktop: the Medium dock's 72 px plate 16 px from the left edge, centred on the
// screen (the compositor's place for it: 33..867); the card 8 px beside it (x 96), centred on it
// (y 100).
assert.deepStrictEqual(besideDock("left", { x: 16, y: 33, width: 72, height: 834 }, area, card), { x: 96, y: 100 });
// On the right: the plate at 1352..1424, the card's right edge 8 px from it.
assert.deepStrictEqual(besideDock("right", { x: 1352, y: 33, width: 72, height: 834 }, area, card), { x: 664, y: 100 });
// A short dock high up: the card centred on it would reach under the top bar; it is kept below.
assert.strictEqual(besideDock("left", { x: 16, y: 40, width: 72, height: 200 }, area, card).y, 42);
// And low down: kept 8 px above the bottom.
assert.strictEqual(besideDock("left", { x: 16, y: 800, width: 72, height: 90 }, area, card).y, 192);
// The Small dock's 60 px plate.
assert.strictEqual(besideDock("left", { x: 16, y: 50, width: 60, height: 700 }, area, card).x, 84);
// At the bottom, or without a plate known: null (the card stays centred on the screen).
assert.strictEqual(besideDock("bottom", { x: 300, y: 812, width: 840, height: 72 }, area, card), null);
assert.strictEqual(besideDock("", { x: 0, y: 0, width: 0, height: 0 }, area, card), null);
assert.strictEqual(besideDock("left", { x: 16, y: 50, width: 0, height: 0 }, area, card), null);
console.log("beside: all checks passed");
