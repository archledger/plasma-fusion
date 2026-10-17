// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the tablet script's contents/ui/TopBar.js (board Island.dc.html): which KWin windows are
// top bars, and the script that tells each screen's live chips whether its bar is hidden, run here
// against a model of Plasma's desktop scripting. Run: node packages/kwin/tests/tablet-topbar.test.js
// (81-kwin-tablet.sh runs it).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "scripts", "plasmafusion-tablet", "contents", "ui", "TopBar.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { isTopBar, barState, barScript } = globalThis;

// Windows: the laptop screen at 0,0 and a monitor to its right at 1440,0.
const laptop = { x: 0, y: 0, width: 1440, height: 900 };
const monitor = { x: 1440, y: 0, width: 1920, height: 1080 };
const win = (o) => Object.assign({ dock: true, resourceClass: "plasmashell", x: 0, y: 0, width: 1440, height: 34 }, o);
assert.ok(isTopBar(win({}), laptop), "the bar along the top of the laptop screen");
assert.ok(isTopBar(win({ x: 1440, width: 1920 }), monitor), "the monitor's bar");
assert.ok(!isTopBar(win({ x: 1440, width: 1920 }), laptop), "on another output: not this output's bar");
assert.ok(!isTopBar(win({ x: 300, y: 812, width: 840, height: 88 }), laptop), "the dock");
assert.ok(!isTopBar(win({ x: 16, y: 33, width: 72, height: 834 }), laptop), "a dock on the left");
assert.ok(!isTopBar(win({ x: 520, y: 4, width: 400, height: 32 }), laptop), "a window at the top, not along it");
assert.ok(!isTopBar(win({ height: 300 }), laptop), "a panel window a third of the screen high along the top: not the bar");
assert.ok(!isTopBar(win({ resourceClass: "firefox" }), laptop), "not plasmashell's");
assert.ok(!isTopBar(win({ dock: false }), laptop), "not a panel");
assert.ok(!isTopBar(win({}), null), "no output");

// The state in a fixed order: the same bars send the same script.
assert.deepStrictEqual(barState([{ x: 1440, y: 0, hidden: false }, { x: 0, y: 0, hidden: true }]),
                       [{ x: 0, y: 0, hidden: true }, { x: 1440, y: 0, hidden: false }]);
assert.strictEqual(barScript([{ x: 1440, y: 0, hidden: false }, { x: 0, y: 0, hidden: true }]),
                   barScript([{ x: 0, y: 0, hidden: true }, { x: 1440, y: 0, hidden: false }]));

// A shell with screens and panels {screen, widgets}. Plasma 6.8 keeps a panel of a screen that is
// gone on that screen; its widgets can be listed, but the script must not look for that screen
// (the model throws).
function shell(screens, specs) {
    const panels = specs.map((spec, i) => Object.assign({ id: i + 1, widgetConfig: {} }, spec));
    const context = vm.createContext({
        screenCount: screens.length,
        screenGeometry(i) {
            if (!(i >= 0 && i < screens.length)) {
                throw new Error("screenGeometry of missing screen " + i);
            }
            const g = screens[i];
            return { x: g.x, y: g.y, width: g.width, height: g.height };
        },
        panels() {
            return panels.map((p) => ({
                get screen() { return p.screen; },
                widgets(type) {
                    return p.widgets.filter((w) => !type || w === type).map(() => ({
                        currentConfigGroup: [],
                        readConfig(key, fallback) { const v = p.widgetConfig[key]; return v === undefined ? fallback : v; },
                        writeConfig(key, value) { p.widgetConfig[key] = value; },
                    }));
                },
            }));
        },
        print(text) { context.out = String(text); },
    });
    return {
        panels,
        run(bars) { vm.runInContext(barScript(bars), context); return context.out; },
    };
}
const CHIPS = "org.plasmafusion.livechips";
{
    const s = shell([laptop, monitor], [
        { screen: 0, widgets: ["org.plasmafusion.appname", CHIPS] },
        { screen: 1, widgets: ["org.plasmafusion.appname", CHIPS] },
        { screen: 0, widgets: ["org.plasmafusion.dock"] },
    ]);
    assert.strictEqual(s.run([{ x: 0, y: 0, hidden: true }, { x: 1440, y: 0, hidden: false }]), "island: 2 widgets, 1 changed");
    assert.deepStrictEqual([s.panels[0].widgetConfig.barHidden, s.panels[1].widgetConfig.barHidden], [true, undefined],
                           "the laptop's bar is hidden; the monitor's shows");
    assert.strictEqual(s.run([{ x: 0, y: 0, hidden: true }, { x: 1440, y: 0, hidden: false }]), "island: 2 widgets, 0 changed",
                       "nothing written again");
    assert.strictEqual(s.run([{ x: 0, y: 0, hidden: false }, { x: 1440, y: 0, hidden: true }]), "island: 2 widgets, 2 changed");
    assert.deepStrictEqual([s.panels[0].widgetConfig.barHidden, s.panels[1].widgetConfig.barHidden], [false, true]);
    // No bar window known any more (plasmashell's windows went): every island goes.
    assert.strictEqual(s.run([]), "island: 2 widgets, 1 changed");
    assert.strictEqual(s.panels[1].widgetConfig.barHidden, false);
    // A value written as text by an older run reads as true.
    s.panels[0].widgetConfig.barHidden = "true";
    assert.strictEqual(s.run([{ x: 0, y: 0, hidden: true }]), "island: 2 widgets, 0 changed");
}
{
    // A panel of a screen that is gone is skipped.
    const s = shell([laptop], [{ screen: 0, widgets: [CHIPS] }, { screen: 2, widgets: [CHIPS] }]);
    assert.strictEqual(s.run([{ x: 0, y: 0, hidden: true }]), "island: 1 widgets, 1 changed");
}
console.log("tablet-topbar.test.js: ok");
