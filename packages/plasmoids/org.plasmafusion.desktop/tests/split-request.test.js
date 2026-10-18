// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of splitScript() in contents/ui/code/home.js (not installed): the home screen's split
// request reaches one dock, the one on its own screen, against a model of Plasma's desktop
// scripting (panels() with their screen and widgets). Run: node tests/split-request.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");
const file = path.join(__dirname, "..", "contents", "ui", "code", "home.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { splitScript } = globalThis;
assert.strictEqual(typeof splitScript, "function", "home.js does not define splitScript");

// A model of desktop scripting: each panel has a screen and widgets; a widget records its writes.
function shell(layout) {
    const writes = [];
    const panels = layout.map(({ screen, widgets }) => ({
        screen,
        widgets: (name) => widgets.filter((w) => w === name).map((w, i) => ({
            currentConfigGroup: [],
            writeConfig(key, value) { writes.push({ screen, key, value, group: this.currentConfigGroup.join("/"), index: i }); },
        })),
    }));
    return { panels: () => panels, writes };
}
function run(layout, screen) {
    const s = shell(layout);
    vm.runInNewContext(splitScript("right", "org.kde.konsole.desktop", screen, 1792350000000), { panels: s.panels });
    return s.writes;
}
const DOCK = "org.plasmafusion.dock";
const want = (screen) => [{ screen, key: "splitRequest", value: "right:1792350000000:org.kde.konsole.desktop", group: "General", index: 0 }];

// A dock on every screen: only the dock of the home screen's screen gets the request.
const everyScreen = [{ screen: 0, widgets: ["org.plasmafusion.appname", DOCK] }, { screen: 1, widgets: [DOCK] }];
assert.deepStrictEqual(run(everyScreen, 1), want(1));
assert.deepStrictEqual(run(everyScreen, 0), want(0));
// The dock on the main screen only: a home screen on another screen hands it to that one dock.
assert.deepStrictEqual(run([{ screen: 0, widgets: [DOCK] }, { screen: 1, widgets: ["org.plasmafusion.appname"] }], 1), want(0));
// A dock of a screen that is gone (screen -1 on Plasma 6.7) is not this screen's.
assert.deepStrictEqual(run([{ screen: -1, widgets: [DOCK] }, { screen: 0, widgets: [DOCK] }], 0), want(0));
// Two docks on one screen: one request, not two.
assert.strictEqual(run([{ screen: 0, widgets: [DOCK, DOCK] }], 0).length, 1);
// No dock at all: nothing written, no error.
assert.deepStrictEqual(run([{ screen: 0, widgets: ["org.plasmafusion.appname"] }], 0), []);
assert.deepStrictEqual(run([], 0), []);
// The value is a quoted literal: the app id cannot end the string.
assert.ok(splitScript("left", 'a".desktop', 0, 1).includes('"left:1:a\\".desktop"'));
console.log("split-request.test.js: ok");
