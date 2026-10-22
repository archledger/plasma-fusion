// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Run: node packages/kwin/tests/snap-directional.test.js (also in 80-kwin.sh).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const file = path.join(__dirname, "..", "scripts", "plasmafusion-snap", "contents", "ui", "Directional.js");
vm.runInThisContext(fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, ""), { filename: file });

// Columns are Left, Right, Up, Down. Rows are untiled, halves, then the four corners.
const expected = [
    [0, 1, 2, 3],
    [0, 1, 4, 6], [0, 1, 5, 7], [4, 5, 2, 3], [6, 7, 2, 3],
    [4, 5, 4, 6], [4, 5, 5, 7], [6, 7, 4, 6], [6, 7, 5, 7]
];
const directions = ["left", "right", "up", "down"];
for (let role = -1; role < 8; ++role) {
    directions.forEach((direction, i) => {
        const next = directionalRole(role, direction);
        assert.strictEqual(next, expected[role + 1][i], `${role} then ${direction}`);
        assert.strictEqual(directionalRole(next, direction), next, "repeats are idempotent");
    });
}
assert.strictEqual(directionalRole(42, "left"), 0, "unknown tile starts a half");
assert.strictEqual(directionalRole(4, "bogus"), 4, "unknown direction is harmless");
for (const [a, b] of [["left", "up"], ["left", "down"], ["right", "up"], ["right", "down"]]) {
    assert.strictEqual(directionalRole(directionalRole(-1, a), b),
                       directionalRole(directionalRole(-1, b), a), "corner order is symmetric");
}

const center = { x: 0, y: 0, width: 1000, height: 800 };
const rect = (x, y, width = 1000, height = 800) => ({ x, y, width, height });
const screens = [center, rect(1000, 0), rect(-1000, 0), rect(0, -800), rect(0, 800)];
assert.strictEqual(directionalNeighbour(screens, center, "left"), 2);
assert.strictEqual(directionalNeighbour(screens, center, "right"), 1);
assert.strictEqual(directionalNeighbour(screens, center, "up"), 3);
assert.strictEqual(directionalNeighbour(screens, center, "down"), 4);
directions.forEach(d => assert.strictEqual(directionalNeighbour([center], center, d), -1));
assert.strictEqual(directionalNeighbour(screens, center, "bogus"), -1);
assert.strictEqual(directionalNeighbour([rect(1000, 800)], center, "right"), -1,
                   "corner-only contact is not an adjacent screen");
assert.strictEqual(directionalNeighbour([rect(1000, 900), rect(1040, 100)], center, "right"), 1,
                   "a screen with perpendicular overlap wins, even across a gap");
assert.strictEqual(directionalNeighbour([rect(1000, 700), rect(1000, 0)], center, "right"), 1,
                   "equal edge distance prefers better center alignment");
assert.strictEqual(directionalNeighbour([rect(1000, 0), rect(1010, 0)], center, "right"), 0,
                   "nearest facing edge wins");
assert.strictEqual(directionalNeighbour([rect(900, 0)], center, "right"), -1,
                   "mirrored or overlapping outputs are not adjacent");
console.log("snap-directional: role matrix, repeat/order invariants and spatial monitors passed");
