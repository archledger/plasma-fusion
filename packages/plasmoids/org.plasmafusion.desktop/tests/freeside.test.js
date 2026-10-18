// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of freeSide(), sameApp() and sameFree() in contents/ui/code/home.js (not installed): the
// tablet home screen's free side (board TabletSplit.dc.html). Run: node tests/freeside.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");
const file = path.join(__dirname, "..", "contents", "ui", "code", "home.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { freeSide, sameApp, sameFree } = globalThis;
assert.strictEqual(typeof freeSide, "function", "home.js does not define freeSide");

// The ThinkPad in tablet posture (1920 x 1200 at 4/3: 1440 x 900 logical): the work area under the
// 45 px top bar and above the dock's 21 px strip, in the home screen's coordinates (its origin is
// the work area's corner).
const area = { x: 0, y: 0, width: 1440, height: 834 };
// Quick tiles with the snap script's 6 px gaps (the split from the dock: Dolphin 6,51 711x823 on
// the screen, docs/parts/shell-dock.md).
const left = { x: 6, y: 6, width: 711, height: 822, appId: "org.kde.dolphin" };
const right = { x: 723, y: 6, width: 711, height: 822, appId: "org.kde.kwrite" };

// One app in the left half: the right part is free, from its edge to the area's.
assert.deepStrictEqual(freeSide([left], area), { side: "right", x: 717, y: 0, width: 723, height: 834, appId: "org.kde.dolphin" });
// In the right half: the left part.
assert.deepStrictEqual(freeSide([right], area), { side: "left", x: 0, y: 0, width: 723, height: 834, appId: "org.kde.kwrite" });
// Two apps side by side: nothing is free.
assert.strictEqual(freeSide([left, right], area), null);
assert.strictEqual(freeSide([right, left], area), null);
// Nothing shown (the home screen), or a maximized app (at both edges): nothing.
assert.strictEqual(freeSide([], area), null);
assert.strictEqual(freeSide(null, area), null);
assert.strictEqual(freeSide([{ x: 0, y: 0, width: 1440, height: 834, appId: "a" }], area), null);
// A window that is not top to bottom (a dialog, a window the user made smaller): nothing.
assert.strictEqual(freeSide([{ x: 6, y: 6, width: 711, height: 500, appId: "a" }], area), null);
assert.strictEqual(freeSide([{ x: 6, y: 200, width: 711, height: 628, appId: "a" }], area), null);
// A window away from both edges: nothing.
assert.strictEqual(freeSide([{ x: 300, y: 6, width: 711, height: 822, appId: "a" }], area), null);
// The split divider's 2/3 and 1/3 (docs/parts/kwin-tablet.md: 951 | 471): the rest is free...
assert.deepStrictEqual(freeSide([{ x: 6, y: 6, width: 951, height: 822, appId: "a" }], area),
                       { side: "right", x: 957, y: 0, width: 483, height: 834, appId: "a" });
assert.deepStrictEqual(freeSide([{ x: 963, y: 6, width: 471, height: 822, appId: "b" }], area),
                       { side: "left", x: 0, y: 0, width: 963, height: 834, appId: "b" });
// ...but a sliver too narrow for a column of apps is not.
assert.strictEqual(freeSide([{ x: 6, y: 6, width: 1220, height: 822, appId: "a" }], area), null);
// Another window over the free part (a floating window, a maximized one under the tiled app):
// nothing; one inside the app's half (its dialog) leaves the free part free.
assert.strictEqual(freeSide([left, { x: 900, y: 200, width: 400, height: 300, appId: "c" }], area), null);
assert.strictEqual(freeSide([left, { x: 0, y: 0, width: 1440, height: 834, appId: "c" }], area), null);
assert.deepStrictEqual(freeSide([left, { x: 150, y: 200, width: 400, height: 300, appId: "org.kde.dolphin" }], area).side, "right");
// One touching the free part by the gaps' width only does not cover it.
assert.strictEqual(freeSide([left, { x: 700, y: 6, width: 30, height: 822, appId: "c" }], area).side, "right");
// Windows without a size (not mapped yet) are not shown.
assert.strictEqual(freeSide([left, { x: 800, y: 100, width: 0, height: 0, appId: "c" }], area).side, "right");
// A work area that does not start at 0 (a screen's coordinates).
assert.deepStrictEqual(freeSide([{ x: 1926, y: 51, width: 711, height: 822, appId: "a" }], { x: 1920, y: 45, width: 1440, height: 834 }),
                       { side: "right", x: 2637, y: 45, width: 723, height: 834, appId: "a" });
// A portrait screen (900 x 1395 logical): halves side by side too, each 444 px.
assert.deepStrictEqual(freeSide([{ x: 6, y: 6, width: 441, height: 1383, appId: "a" }], { x: 0, y: 0, width: 900, height: 1395 }),
                       { side: "right", x: 447, y: 0, width: 453, height: 1395, appId: "a" });

// The same app under its names.
assert.ok(sameApp("org.kde.dolphin.desktop", "org.kde.dolphin"));
assert.ok(sameApp("applications:org.kde.dolphin.desktop", "org.kde.dolphin.desktop"));
assert.ok(!sameApp("org.kde.dolphin", "org.kde.kwrite"));
assert.ok(!sameApp("", ""));
assert.ok(!sameApp(undefined, null));

// Unchanged answers.
assert.ok(sameFree(null, null));
assert.ok(!sameFree(null, freeSide([left], area)));
assert.ok(sameFree(freeSide([left], area), freeSide([{ ...left, width: 711.2 }], area)));
assert.ok(!sameFree(freeSide([left], area), freeSide([right], area)));
assert.ok(!sameFree(freeSide([left], area), freeSide([{ ...left, appId: "x" }], area)));
console.log("freeside.test.js: ok");
