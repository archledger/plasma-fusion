// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of occupiedTiles() and placeFor() in plasmafusion-tablet's Snap.js: the half a window takes
// when Full screen is switched off in tablet posture (board TabletSnap.dc.html).
// Run: node tests/tablet-snap.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");
const file = path.join(__dirname, "..", "scripts", "plasmafusion-tablet", "contents", "ui", "Snap.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { placeFor, occupiedTiles, isLeft, isRight } = globalThis;
assert.strictEqual(typeof placeFor, "function", "Snap.js does not define placeFor");

const LEFT = { x: 0, y: 0, width: 0.5, height: 1 };
const RIGHT = { x: 0.5, y: 0, width: 0.5, height: 1 };
const LEFT_THIRD = { x: 0, y: 0, width: 1 / 3, height: 1 };
const LEFT_TWO_THIRDS = { x: 0, y: 0, width: 2 / 3, height: 1 };
const RIGHT_THIRD = { x: 2 / 3, y: 0, width: 1 / 3, height: 1 };
const RIGHT_TWO_THIRDS = { x: 1 / 3, y: 0, width: 2 / 3, height: 1 };
const TOP = { x: 0, y: 0, width: 1, height: 0.5 };
const QUARTER = { x: 0.5, y: 0.5, width: 0.5, height: 0.5 };
const near = (place, side, fraction, reset) => {
    assert.ok(place, `no place, want ${side}`);
    assert.strictEqual(place.side, side);
    assert.ok(Math.abs(place.fraction - fraction) < 1e-9, `fraction ${place.fraction}, want ${fraction}`);
    assert.strictEqual(place.reset, reset);
};

// Nothing tiled (alone, or over a maximized window): the right half, the split back in the middle.
near(placeFor([], 300, 1440), "right", 0.5, true);
// The other half free: that side, as wide as the other window leaves it.
near(placeFor([LEFT], 300, 1440), "right", 0.5, false);
near(placeFor([RIGHT], 300, 1440), "left", 0.5, false);
near(placeFor([LEFT_THIRD], 300, 1440), "right", 2 / 3, false);
near(placeFor([LEFT_TWO_THIRDS], 300, 1440), "right", 1 / 3, false);
near(placeFor([RIGHT_TWO_THIRDS], 300, 1440), "left", 1 / 3, false);
near(placeFor([RIGHT_THIRD], 300, 1440), "left", 2 / 3, false);
// Both taken: into the right tile.
near(placeFor([LEFT, RIGHT], 300, 1440), "right", 0.5, false);
near(placeFor([LEFT_TWO_THIRDS, RIGHT_THIRD], 300, 1440), "right", 1 / 3, false);
// Tiles that are not a left or right half (a top half, a quarter) do not take a side.
near(placeFor([TOP, QUARTER], 300, 1440), "right", 0.5, true);
// The minimum width against the side's own width (8 px for the gaps): a half, a third, two thirds.
assert.strictEqual(placeFor([], 713, 1440), null);
near(placeFor([], 712, 1440), "right", 0.5, true);
assert.strictEqual(placeFor([LEFT_TWO_THIRDS], 600, 1440), null);   // 480 px left over
near(placeFor([LEFT_TWO_THIRDS], 472, 1440), "right", 1 / 3, false);
near(placeFor([LEFT_THIRD], 900, 1440), "right", 2 / 3, false);     // 960 px: wider than a half fits
assert.strictEqual(placeFor([LEFT, RIGHT], 900, 1440), null);
// The halves' test.
assert.ok(isLeft(LEFT) && !isRight(LEFT) && isRight(RIGHT) && !isLeft(RIGHT));
assert.ok(!isLeft(TOP) && !isRight(TOP) && !isLeft(null) && !isRight(undefined));

// Which windows' tiles count: shown with the window on its screen, desktop and activity.
const SCREEN = { name: "eDP-1" }, OTHER_SCREEN = { name: "HDMI-A-1" };
const w = { output: SCREEN };
const win = (tile, more) => Object.assign({ normalWindow: true, output: SCREEN, desktops: ["d1"], activities: [], tile: tile ? { relativeGeometry: tile } : null }, more || {});
const list = [
    w,                                                            // the window itself
    win(LEFT),                                                    // counts
    win(RIGHT, { activities: ["other"] }),                        // another activity: not shown
    win(RIGHT, { output: OTHER_SCREEN }),                         // another screen
    win(RIGHT, { desktops: ["d2"] }),                             // another desktop
    win(RIGHT, { minimized: true }),                              // minimized
    win(RIGHT, { normalWindow: false }),                          // a panel or a dialog
    win(RIGHT, { deleted: true }),                                // closing
    win(null),                                                    // not tiled
];
assert.deepStrictEqual(occupiedTiles(w, list, "d1", "a1"), [LEFT]);
// On every desktop, on this activity or on every activity (an empty list): they count.
assert.deepStrictEqual(occupiedTiles(w, [win(RIGHT, { onAllDesktops: true, desktops: [] })], "d1", "a1"), [RIGHT]);
assert.deepStrictEqual(occupiedTiles(w, [win(RIGHT, { activities: ["a1", "other"] })], "d1", "a1"), [RIGHT]);
// The reviewer's case: a right tile here, a left one on another activity - the free left half.
near(placeFor(occupiedTiles(w, [win(RIGHT, { activities: ["a1"] }), win(LEFT, { activities: ["other"] })], "d1", "a1"), 300, 1440), "left", 0.5, false);
console.log("tablet-snap.test.js: ok");
