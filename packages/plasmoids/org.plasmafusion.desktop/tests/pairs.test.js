// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/ui/code/pairs.js (not installed): saved app pairs on the home screen - a
// favourite's pair id, the pair and its apps from their desktop files as QtCore Settings reads them,
// the label, the dock's pairRequest against a model of Plasma's desktop scripting, and the helper's
// command. Run: node tests/pairs.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");
const file = path.join(__dirname, "..", "contents", "ui", "code", "pairs.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { pairId, validApp, snapShare, readPair, readApp, label, iconName, pairScript, helperCommand } = globalThis;
assert.strictEqual(typeof pairId, "function", "pairs.js does not define pairId");

// pairId: only the pair entries the helper writes.
assert.strictEqual(pairId("applications:org.plasmafusion.pair-17923892421.desktop"), "org.plasmafusion.pair-17923892421.desktop");
assert.strictEqual(pairId("org.plasmafusion.pair-17923892421.desktop"), "org.plasmafusion.pair-17923892421.desktop"); // the model's id
assert.strictEqual(pairId("applications:org.kde.dolphin.desktop"), "");
assert.strictEqual(pairId("org.kde.dolphin.desktop"), "");
assert.strictEqual(pairId("applications:org.plasmafusion.pair-.desktop"), "");
assert.strictEqual(pairId("applications:org.plasmafusion.pair-1/../x.desktop"), "");
assert.strictEqual(pairId("file:///home/u/org.plasmafusion.pair-1.desktop"), "");
assert.strictEqual(pairId(undefined), "");
assert.ok(validApp("org.kde.dolphin.desktop") && validApp("firefox.desktop"));
assert.ok(!validApp("firefox") && !validApp("../x.desktop") && !validApp(""));

// snapShare: the divider's 1/3, 1/2, 2/3.
assert.deepStrictEqual([0.3, 0.3333, 0.41, 0.42, 0.5, 0.58, 0.59, 0.6667, 0.9, "x", undefined].map(snapShare),
                       [0.3333, 0.3333, 0.3333, 0.5, 0.5, 0.5, 0.6667, 0.6667, 0.6667, 0.5, 0.5]);

// A desktop file as QtCore Settings reads it: "Desktop Entry/KEY", a value with commas as a list.
function reader(text) {
    const values = {};
    let group = "";
    for (const line of text.split("\n")) {
        const g = line.match(/^\[(.*)\]$/);
        if (g) { group = g[1]; continue; }
        const kv = line.match(/^([^=]+)=(.*)$/);
        if (kv) { values[group + "/" + kv[1]] = kv[2].includes(",") ? kv[2].split(",") : kv[2]; }
    }
    return (key) => values[key];
}
const entry = reader(`[Desktop Entry]
Type=Application
Name=Dolphin · Firefox
NoDisplay=true
X-PlasmaFusion-PairLeft=org.kde.dolphin.desktop
X-PlasmaFusion-PairRight=firefox.desktop
X-PlasmaFusion-PairShare=0.3333`);
assert.deepStrictEqual(readPair(entry), { left: "org.kde.dolphin.desktop", right: "firefox.desktop", share: 0.3333 });
assert.strictEqual(readPair(reader("[Desktop Entry]\nName=Kate")), null);              // not a pair's entry
assert.strictEqual(readPair(reader("[Desktop Entry]\nX-PlasmaFusion-PairLeft=a.desktop\nX-PlasmaFusion-PairRight=a.desktop")), null); // one app twice
assert.strictEqual(readPair(reader("[Desktop Entry]\nX-PlasmaFusion-PairLeft=../a.desktop\nX-PlasmaFusion-PairRight=b.desktop")), null);
assert.strictEqual(readPair(reader("[Desktop Entry]\nX-PlasmaFusion-PairLeft=a.desktop\nX-PlasmaFusion-PairRight=b.desktop")).share, 0.5); // no split: half
assert.strictEqual(readPair(() => undefined), null);                                    // no file

// readApp: the name in the asked language, the icon; null without a Desktop Entry name.
const dolphin = reader(`[Desktop Entry]
Name=Dolphin
Name[de]=Dolphin (de)
Name[pt_BR]=Dolphin (pt_BR)
Icon=system-file-manager

[Desktop Action new]
Name=New Window`);
assert.deepStrictEqual(readApp(dolphin, "C"), { name: "Dolphin", icon: "system-file-manager" });
assert.deepStrictEqual(readApp(dolphin, "de_DE"), { name: "Dolphin (de)", icon: "system-file-manager" });
assert.deepStrictEqual(readApp(dolphin, "pt_BR"), { name: "Dolphin (pt_BR)", icon: "system-file-manager" });
assert.strictEqual(readApp(dolphin, "").name, "Dolphin");
assert.strictEqual(readApp(reader("[Desktop Entry]\nName=Foo, Bar\nIcon=x")).name, "Foo, Bar"); // commas
assert.strictEqual(readApp(reader("[Desktop Entry]\nName=Foo")).icon, "");
assert.strictEqual(readApp(() => undefined, "de"), null);                               // not installed

assert.strictEqual(label("Dolphin", "Firefox"), "Dolphin · Firefox");
assert.strictEqual(iconName("org.kde.dolphin.desktop"), "org.kde.dolphin");

// pairScript: one dock, the one on the home screen's own screen, else any; the request's text.
function shell(layout) {
    const writes = [];
    const panels = layout.map(({ screen, widgets }) => ({
        screen,
        widgets: (name) => widgets.filter((w) => w === name).map(() => ({
            currentConfigGroup: [],
            writeConfig(key, value) { writes.push({ screen, key, value, group: this.currentConfigGroup.join("/") }); },
        })),
    }));
    return { panels: () => panels, writes };
}
const pair = { left: "org.kde.dolphin.desktop", right: "firefox.desktop", share: 0.3333 };
for (const [layout, screen, expect] of [
    [[{ screen: 0, widgets: ["org.plasmafusion.dock"] }, { screen: 1, widgets: ["org.plasmafusion.dock"] }], 1, 1],
    [[{ screen: 0, widgets: ["org.plasmafusion.dock"] }, { screen: 1, widgets: ["org.plasmafusion.dock"] }], 0, 0],
    [[{ screen: 0, widgets: ["org.plasmafusion.dock"] }, { screen: 1, widgets: ["other"] }], 1, 0],
]) {
    const s = shell(layout);
    vm.runInNewContext(pairScript(pair, screen, 42), { panels: s.panels });
    assert.deepStrictEqual(s.writes, [{ screen: expect, key: "pairRequest", value: "42:org.kde.dolphin.desktop:firefox.desktop:0.3333", group: "General" }]);
}
const none = shell([{ screen: 0, widgets: ["other"] }]);
vm.runInNewContext(pairScript(pair, 0, 1), { panels: none.panels });
assert.deepStrictEqual(none.writes, []);

// helperCommand: swap and remove of a pair id only, run from the helper directories in order.
const cmd = helperCommand("swap", "org.plasmafusion.pair-1.desktop");
assert.ok(cmd.startsWith("sh -c 'for d in \"$HOME/.local/libexec/plasma-fusion\" /usr/local/libexec/plasma-fusion "));
assert.ok(cmd.includes("exec \"$d/plasma-fusion-app-pair\" swap org.plasmafusion.pair-1.desktop;"));
assert.ok(helperCommand("remove", "org.plasmafusion.pair-1.desktop").includes(" remove org.plasmafusion.pair-1.desktop;"));
assert.strictEqual(helperCommand("save", "org.plasmafusion.pair-1.desktop"), "");
assert.strictEqual(helperCommand("remove", "x.desktop; rm -rf ~"), "");
assert.strictEqual(helperCommand("remove", "org.plasmafusion.pair-1.desktop'"), "");
console.log("pairs.test.js: ok");
