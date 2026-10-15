// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the placement script's contents/ui/Placement.js (the remembering and restoring rules).
// Run: node packages/kwin/tests/placement.test.js (80-kwin.sh runs it).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "scripts", "plasmafusion-placement", "contents", "ui", "Placement.js");
vm.runInThisContext(fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (l) => " ".repeat(l.length)), { filename: pathToFileURL(file).href });
const { appId, valid, parse, serialize, floating, eligible, ignored, onScreen, collides, sameDesktop, restoreRect, restoreFor, remember } = globalThis;

const rect = (x, y, width, height) => ({ x, y, width, height });
const desktop = () => ({ normal: true, transient: false, modal: false, fullScreen: false, tiled: false, minimized: false, maximizeMode: 0 });
const screens = [rect(0, 0, 1440, 900)];

// ---- app id: the desktop file when there is one, else the window class, lowercased
assert.strictEqual(appId("konsole", ""), "konsole");
assert.strictEqual(appId("Org.KDE.Kate", ""), "org.kde.kate");
assert.strictEqual(appId("konsole", "org.kde.konsole"), "org.kde.konsole", "the desktop file wins");
assert.strictEqual(appId("konsole", "/usr/share/applications/org.kde.konsole.desktop"), "org.kde.konsole", "path and .desktop suffix stripped");
assert.strictEqual(appId("", ""), "");
assert.strictEqual(appId(null, undefined), "");

// ---- a held rectangle: four finite numbers at a sane size, rounded
assert.deepStrictEqual(valid(rect(1.4, 2.6, 640, 480)), rect(1, 3, 640, 480));
assert.strictEqual(valid(null), null);
assert.strictEqual(valid("640x480"), null);
assert.strictEqual(valid(rect(0, 0, 10, 10)), null, "too small to be a window");
assert.strictEqual(valid(rect(0, 0, 30000, 480)), null, "absurdly large");
assert.strictEqual(valid(rect(NaN, 0, 640, 480)), null);
assert.deepStrictEqual(valid({ x: "12", y: "8", width: "640", height: "480" }), rect(12, 8, 640, 480), "numeric strings are numbers");

// ---- the file: parse -> serialize -> parse is stable; anything broken is dropped
const memory = { "org.kde.konsole": rect(100, 120, 800, 500), kate: rect(10, 20, 300, 400) };
assert.deepStrictEqual(parse(serialize(memory)), memory, "round trip");
assert.strictEqual(JSON.parse(serialize({})).v, 1, "the format carries its version");
assert.deepStrictEqual(parse(""), {});
assert.deepStrictEqual(parse("not json"), {});
assert.deepStrictEqual(parse('{"v":1}'), {});
assert.deepStrictEqual(parse('{"v":1,"apps":{"a":{"x":1,"y":2,"width":10,"height":600}}}'), {}, "a broken record is dropped");
assert.deepStrictEqual(parse('{"v":1,"apps":{"a":{"x":1,"y":2,"width":640,"height":480},"b":null}}'), { a: rect(1, 2, 640, 480) }, "the rest is kept");

// ---- floating and eligible
assert.ok(floating(desktop()));
assert.ok(!floating({ ...desktop(), maximizeMode: 3 }));
assert.ok(!floating({ ...desktop(), tiled: true }));
assert.ok(!floating({ ...desktop(), fullScreen: true }));
assert.ok(!floating({ ...desktop(), minimized: true }));
assert.ok(eligible(desktop()));
assert.ok(!eligible({ ...desktop(), normal: false }));
assert.ok(!eligible({ ...desktop(), transient: true }));
assert.ok(!eligible({ ...desktop(), modal: true }));
assert.ok(!eligible({ ...desktop(), maximizeMode: 3 }));

// ---- IgnoreApps
assert.ok(ignored("org.kde.konsole", "konsole"), "the last dot-separated part matches");
assert.ok(ignored("konsole", "konsole"));
assert.ok(ignored("org.kde.konsole", " kate , KONSOLE "), "spaces and case");
assert.ok(!ignored("org.kde.konsole", "sole"), "not a partial word");
assert.ok(!ignored("org.kde.konsole", ""));
assert.ok(!ignored("org.kde.konsole", "kate,code"));

// ---- the remembered spot must have its centre on a screen that exists now
const two = [rect(0, 0, 1440, 900), rect(1440, 0, 1920, 1080)];
assert.ok(onScreen(rect(200, 100, 800, 500), screens));
assert.ok(onScreen(rect(2800, 100, 800, 500), two), "the second screen");
assert.ok(!onScreen(rect(4000, 100, 800, 500), two), "beyond every screen");
assert.ok(!onScreen(rect(1050, 100, 800, 500), [rect(0, 0, 1400, 900), rect(1500, 0, 800, 900)]), "in the gap between screens");
assert.ok(onScreen(rect(-900, 100, 800, 500), [rect(-1920, 0, 1920, 1080), rect(0, 0, 1440, 900)]), "a screen left of the origin");

// ---- the stack guard
assert.ok(collides(rect(100, 100, 640, 480), [rect(104, 103, 700, 500)]));
assert.ok(!collides(rect(100, 100, 640, 480), [rect(110, 100, 700, 500)]));
assert.ok(!collides(rect(100, 100, 640, 480), []));
assert.ok(collides(rect(100, 100, 640, 480), [rect(92, 92, 640, 480)], 8), "exactly the tolerance");
assert.ok(!collides(rect(100, 100, 640, 480), [rect(91, 100, 640, 480)], 8), "one past the tolerance");

// ---- the guard's desktop scope
assert.ok(sameDesktop({ allDesktops: false, desktops: [1, 2] }, { allDesktops: false, desktops: [2] }), "a shared desktop");
assert.ok(!sameDesktop({ allDesktops: false, desktops: [1] }, { allDesktops: false, desktops: [2, 3] }), "other desktops only");
assert.ok(sameDesktop({ allDesktops: true, desktops: [] }, { allDesktops: false, desktops: [3] }), "an all-desktops window");
assert.ok(!sameDesktop({ allDesktops: false, desktops: [] }, { allDesktops: false, desktops: [] }), "no desktop known");

// ---- the rectangle given back
assert.deepStrictEqual(restoreRect(rect(5, 6, 640, 480), rect(0, 0, 800, 600), true), rect(5, 6, 640, 480));
assert.deepStrictEqual(restoreRect(rect(5, 6, 640, 480), rect(0, 0, 800, 600), false), rect(5, 6, 800, 600), "the size the window opened with");

// ---- the whole decision
const saved = rect(100, 100, 640, 480);
const current = rect(400, 300, 800, 600);
assert.deepStrictEqual(restoreFor("konsole", desktop(), saved, screens, [], "", true, current), saved);
assert.deepStrictEqual(restoreFor("konsole", desktop(), saved, screens, [], "", false, current), rect(100, 100, 800, 600));
assert.strictEqual(restoreFor("konsole", desktop(), saved, screens, [], "konsole", true, current), null, "the app is ignored");
assert.strictEqual(restoreFor("konsole", desktop(), undefined, screens, [], "", true, current), null, "nothing remembered yet");
assert.strictEqual(restoreFor("konsole", desktop(), rect(4000, 100, 640, 480), screens, [], "", true, current), null, "the spot is off-screen");
assert.strictEqual(restoreFor("konsole", desktop(), saved, screens, [rect(103, 97, 800, 500)], "", true, current), null, "an instance already holds the spot");
assert.strictEqual(restoreFor("konsole", { ...desktop(), maximizeMode: 3 }, saved, screens, [], "", true, current), null, "opened maximized keeps KWin's placement");
assert.strictEqual(restoreFor("konsole", { ...desktop(), transient: true }, saved, screens, [], "", true, current), null, "a dialog keeps its parent placement");

// ---- remembering
const apps = {};
assert.strictEqual(remember(apps, "konsole", rect(100, 100, 640, 480)), true);
assert.deepStrictEqual(apps.konsole, rect(100, 100, 640, 480));
assert.strictEqual(remember(apps, "konsole", rect(100, 100, 640, 480)), false, "no change, no write");
assert.strictEqual(remember(apps, "konsole", rect(100.2, 100.3, 640, 480)), false, "equal after rounding");
assert.strictEqual(remember(apps, "konsole", rect(101, 100, 640, 480)), true);
assert.strictEqual(remember(apps, "konsole", rect(0, 0, 1, 1)), false, "never an invalid record");
assert.strictEqual(apps.konsole.x, 101, "the invalid write left the record alone");

console.log("placement.test.js: ok");
