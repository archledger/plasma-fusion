// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the tablet script's contents/ui/Panels.js: the panel script it sends to plasmashell, run
// here against a model of Plasma's desktop scripting, and when it asks again. Run: node
// packages/kwin/tests/tablet-panels.test.js (81-kwin-tablet.sh runs it).
//
// The model's panels behave like WorkspaceScripting::Panel: height and hiding come from the
// panel's window, or without one from its config for its screen. Plasma 6.8 keeps a panel whose
// screen is gone on that screen, and the config of a missing screen is an invalid KConfigGroup:
// plasmashell crashes on the read (the model throws "plasmashell crashed"). Plasma 6.7 reports such
// a panel on screen -1 and reads the first screen's config.
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "scripts", "plasmafusion-tablet", "contents", "ui", "Panels.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { panelScript, retryDelay, notReady, retryLimit } = globalThis;

const TOP = ["org.plasmafusion.appname", "org.plasmafusion.clockpill", "org.plasmafusion.quicksettings"];
const DOCK = ["org.plasmafusion.dock"];

// A shell with `screens` screens and these panels: {screen, widgets, height, hiding, config}.
function shell(plasma, screens, specs, desktops = 1, rc = {}) {
    const touched = [];
    const panels = specs.map((spec, index) => {
        const panel = Object.assign({ id: index + 1, height: 34, hiding: "none", config: {}, group: "" }, spec);
        panel.widgetConfig = {};
        return panel;
    });
    function view(panel, what) {
        const onScreen = panel.screen >= 0 && panel.screen < screens;
        // 6.7: a panel without a screen is on -1, and the first screen's config is read instead.
        const screenForConfig = Math.max(panel.screen, 0);
        if (!onScreen) {
            touched.push(panel.id + " " + what);
        }
        if (screenForConfig >= screens) {
            throw new Error("plasmashell crashed: panel " + panel.id + " " + what + " on missing screen " + panel.screen);
        }
    }
    function widget(panel, type, index) {
        return {
            id: panel.id * 100 + index,
            type,
            currentConfigGroup: [],
            readConfig(key, fallback) {
                const v = panel.widgetConfig[key];
                return v === undefined ? fallback : v;
            },
            writeConfig(key, value) {
                panel.widgetConfig[key] = value;
            },
        };
    }
    function object(panel) {
        return {
            get id() { return panel.id; },
            get screen() { return plasma === "6.7" && panel.screen >= screens ? -1 : panel.screen; },
            get location() { return panel.location || (panel.widgets === DOCK ? "bottom" : "top"); },
            set location(where) { view(panel, "location="); panel.location = where; },
            get height() { view(panel, "height"); return panel.height; },
            set height(h) { view(panel, "height="); panel.height = h; },
            get hiding() { view(panel, "hiding"); return panel.hiding; },
            set hiding(h) { view(panel, "hiding="); panel.hiding = h; },
            set currentConfigGroup(g) { panel.group = g.join("/"); },
            get currentConfigGroup() { return panel.group ? panel.group.split("/") : []; },
            readConfig(key, fallback) {
                const v = panel.config[panel.group + "/" + key];
                return v === undefined ? fallback : v;
            },
            writeConfig(key, value) {
                panel.config[panel.group + "/" + key] = value;
            },
            widgets(type) {
                return panel.widgets.map((t, i) => widget(panel, t, i)).filter((w) => !type || w.type === type);
            },
        };
    }
    const printed = [];
    const context = vm.createContext({
        panels: () => panels.map(object),
        desktops: () => new Array(desktops).fill({}),
        screenCount: screens,
        gridUnit: 18,
        // kdeglobals' font for the text scale; plasmafusionrc from RC ("Group/key"), else not set.
        ConfigFile: (file, group) => ({ readEntry: (key) => file === "plasmafusionrc" ? rc[group + "/" + key]
                                                            : "Noto Sans,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" }),
        print: (text) => printed.push(String(text)),
    });
    return {
        panels,
        touched,
        run(tablet, hiding = "dodgewindows", scale = 1) {
            printed.length = 0;
            vm.runInContext(panelScript(tablet, hiding, scale), context);
            return printed.join("\n");
        },
    };
}

// Plasma 6.8 with the top bar of an unplugged second monitor (still on screen 1): the bars on the
// screen get the tablet sizes, the other one is skipped without touching its sizes.
for (const plasma of ["6.8", "6.7"]) {
    const s = shell(plasma, 1, [
        { screen: 0, widgets: TOP, height: 34 },
        { screen: 0, widgets: DOCK, height: 72, hiding: "dodgewindows" },
        { screen: 1, widgets: TOP, height: 34 },
    ]);
    const tablet = s.run(true);
    assert.strictEqual(tablet, "top 44, dock 80 dodgewindows, 1 without a screen skipped", plasma + ": tablet");
    assert.deepStrictEqual(s.touched, [], plasma + ": nothing of the panel without a screen is read or written");
    assert.strictEqual(s.panels[2].height, 34, plasma + ": its height is kept");
    assert.strictEqual(s.panels[0].config["PlasmaFusion/laptopHeight"], 34, plasma + ": the laptop height is saved");
    const laptop = s.run(false);
    assert.strictEqual(laptop, "top 34, dock 72 dodgewindows, 1 without a screen skipped", plasma + ": laptop");
    assert.deepStrictEqual(s.touched, [], plasma + ": still untouched");
}

// The screen comes back (the bar's window appears and the script runs again): it gets the posture.
{
    const s = shell("6.8", 1, [{ screen: 0, widgets: TOP }, { screen: 1, widgets: TOP }]);
    s.run(true);
    const back = shell("6.8", 2, []);
    back.panels.push(...s.panels);
    assert.strictEqual(back.run(true), "top 44, top 44");
}

// A panel on screen -1 (Plasma 6.7) is skipped as well. No screen at all (early in the shell's
// start, or KWin without an output): "not ready", nothing touched.
{
    const s = shell("6.7", 1, [{ screen: 0, widgets: TOP }, { screen: -1, widgets: DOCK, height: 72 }]);
    assert.strictEqual(s.run(true), "top 44, 1 without a screen skipped");
    assert.strictEqual(s.panels[1].height, 72);
    // Every Fusion panel still on -1 (6.7, before the shell has made their windows): asked again.
    const early = shell("6.7", 1, [{ screen: -1, widgets: TOP }, { screen: -1, widgets: DOCK }]);
    assert.strictEqual(early.run(true), "not ready");
    assert.strictEqual(early.panels[0].height, 34);
    const none = shell("6.8", 0, [{ screen: 0, widgets: TOP }]);
    assert.strictEqual(none.run(true), "not ready");
    assert.deepStrictEqual(none.touched, []);
}

// The tablet heights on whole device pixels (4/3), and the dock's strip.
{
    const s = shell("6.8", 1, [{ screen: 0, widgets: TOP }, { screen: 0, widgets: DOCK, height: 72, hiding: "none" }]);
    assert.strictEqual(s.run(true, "dodgewindows", 4 / 3), "top 45, dock 81 dodgewindows");
    assert.strictEqual(s.panels[1].widgetConfig.tabletStripHeight, 21);
    assert.strictEqual(s.run(false, "dodgewindows", 4 / 3), "top 34, dock 72 none");
}

// The dock's size (dockSize, board DockSize.dc.html): its laptop height is that size's plate. A
// Small dock keeps 60 through the posture; a saved height of the old headroom frame (88) and a
// missing one come back as the size's plate (Large 78), not as the Medium dock's 72.
{
    const small = shell("6.8", 1, [{ screen: 0, widgets: TOP }, { screen: 0, widgets: DOCK, height: 60 }]);
    small.panels[1].widgetConfig.dockSize = 0;
    assert.strictEqual(small.run(true), "top 44, dock 80 dodgewindows");
    assert.strictEqual(small.panels[1].config["PlasmaFusion/laptopHeight"], 60);
    assert.strictEqual(small.run(false), "top 34, dock 60 none");
    const large = shell("6.8", 1, [{ screen: 0, widgets: DOCK, height: 80, config: { "PlasmaFusion/tabletApplied": true, "PlasmaFusion/laptopHeight": 88 } }]);
    large.panels[0].widgetConfig.dockSize = 2;
    assert.strictEqual(large.run(false), "dock 78 dodgewindows", "the headroom frame's 88 becomes Large's plate");
    const unsaved = shell("6.8", 1, [{ screen: 0, widgets: DOCK, height: 80, config: { "PlasmaFusion/tabletApplied": true } }]);
    unsaved.panels[0].widgetConfig.dockSize = 2;
    assert.strictEqual(unsaved.run(false), "dock 78 dodgewindows", "no saved height: Large's plate");
}

// A dock on the left (board DockPosition.dc.html): at the bottom in tablet posture, its side kept
// with its height, and back on the left after with its 72 px.
{
    const s = shell("6.8", 1, [{ screen: 0, widgets: TOP }, { screen: 0, widgets: DOCK, height: 72, location: "left" }]);
    assert.strictEqual(s.run(true), "top 44, dock 80 dodgewindows");
    assert.strictEqual(s.panels[1].location, "bottom");
    assert.strictEqual(s.panels[1].config["PlasmaFusion/laptopLocation"], "left");
    assert.strictEqual(s.run(false), "top 34, dock 72 none left");
    assert.strictEqual(s.panels[1].location, "left");
    // A dock that was at the bottom stays there; one without a saved side too.
    const b = shell("6.8", 1, [{ screen: 0, widgets: DOCK, height: 72 }]);
    b.run(true);
    assert.strictEqual(b.panels[0].config["PlasmaFusion/laptopLocation"], "bottom");
    assert.strictEqual(b.run(false), "dock 72 none");
    const unsaved = shell("6.8", 1, [{ screen: 0, widgets: DOCK, height: 80, location: "bottom", config: { "PlasmaFusion/tabletApplied": true } }]);
    assert.strictEqual(unsaved.run(false), "dock 72 dodgewindows");
}

// A top bar that hides (board Island.dc.html): it always shows in tablet posture, its hiding kept
// with its height, and it hides again after; one that never hid stays shown.
{
    const s = shell("6.8", 1, [{ screen: 0, widgets: TOP, hiding: "autohide" }, { screen: 0, widgets: DOCK, height: 72 }]);
    assert.strictEqual(s.run(true), "top 44, dock 80 dodgewindows");
    assert.strictEqual(s.panels[0].hiding, "none");
    assert.strictEqual(s.panels[0].config["PlasmaFusion/laptopHiding"], "autohide");
    assert.strictEqual(s.run(false), "top 34 autohide, dock 72 none");
    const shown = shell("6.8", 1, [{ screen: 0, widgets: TOP }]);
    shown.run(true);
    assert.strictEqual(shown.run(false), "top 34");
    // Set to hide on the settings page while in tablet posture (laptopHiding): it hides after.
    const later = shell("6.8", 1, [{ screen: 0, widgets: TOP, height: 44, config: { "PlasmaFusion/tabletApplied": true, "PlasmaFusion/laptopHiding": "autohide" } }]);
    assert.strictEqual(later.run(false), "top 34 autohide");
}

// The settings page's choice (plasmafusionrc [TopBar] AutoHide): in laptop posture every top bar takes
// it, a bar whose screen was not there when it changed too; in tablet posture the bar shows; not set:
// the bar is left as it is.
{
    const on = shell("6.8", 2, [{ screen: 0, widgets: TOP, hiding: "autohide" }, { screen: 1, widgets: TOP }], 1, { "TopBar/AutoHide": "true" });
    assert.strictEqual(on.run(false), "top 34 autohide, top 34 autohide", "the returned screen's bar hides too");
    assert.strictEqual(on.run(true), "top 44, top 44", "tablet posture: shown");
    assert.strictEqual(on.run(false), "top 34 autohide, top 34 autohide");
    const off = shell("6.8", 1, [{ screen: 0, widgets: TOP, hiding: "autohide" }], 1, { "TopBar/AutoHide": "false" });
    assert.strictEqual(off.run(false), "top 34", "off: shown");
    const unset = shell("6.8", 1, [{ screen: 0, widgets: TOP, hiding: "autohide" }]);
    assert.strictEqual(unset.run(false), "top 34 autohide", "not set: left as it is");
}

// Before the shell has loaded its layout: "not ready", and nothing is changed.
{
    assert.strictEqual(shell("6.8", 1, []).run(true), "not ready");
    const s = shell("6.8", 1, [{ screen: 0, widgets: TOP }], 0);
    assert.strictEqual(s.run(true), "not ready");
    assert.strictEqual(s.panels[0].height, 34);
    assert.ok(notReady("not ready\n") && !notReady("top 44") && !notReady(""));
}

// Asking again: 1, 2, 4, 8, 16, 32 s, then no more.
{
    const delays = [];
    for (let attempt = 0; attempt <= retryLimit; ++attempt) {
        delays.push(retryDelay(attempt));
    }
    assert.deepStrictEqual(delays, [1000, 2000, 4000, 8000, 16000, 32000, -1]);
    assert.strictEqual(retryDelay(-1), -1);
}
console.log("tablet-panels.test.js: ok");
