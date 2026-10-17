// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The Global Theme's desktop layout script and ensure-topbars.js against layout-shell.js (the
// layout scripting runtime): the settings page's choices kept in plasmafusionrc, which both read
// for the bars and widgets they make ("Top bar on every screen", Glass, "Solid top bar next to
// windows"). Run: node packages/look-and-feel/tests/layout.test.js (60-lookandfeel.sh runs it).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const { shell } = require("./layout-shell.js");

const dir = path.join(__dirname, "..", "common", "contents", "layouts");
const LAYOUT = fs.readFileSync(path.join(dir, "org.kde.plasma.desktop-layout.js"), "utf8");
const ENSURE = fs.readFileSync(path.join(dir, "ensure-topbars.js"), "utf8");
const TWO = [[1920, 1080], [1280, 1024]];

const has = (p, type) => p.widgets.some((w) => w.type === type);
const tops = (s) => s.panels.filter((p) => p.location === "top");
const docks = (s) => s.panels.filter((p) => p.location === "bottom");
const all = (s, type) => s.panels.concat(s.desktops).flatMap((c) => c.widgets).filter((w) => w.type === type);
const glass = (w) => ((w.config || {}).General || {}).glass;
function rc(topBar, effects) {
    const f = { plasmafusionrc: {} };
    if (topBar)
        f.plasmafusionrc.TopBar = topBar;
    if (effects)
        f.plasmafusionrc.Effects = effects;
    return f;
}

let n = 0, failed = 0;
function test(name, f) {
    n++;
    try {
        f();
        console.log("ok " + n + " " + name);
    } catch (e) {
        failed++;
        console.log("not ok " + n + " " + name + ": " + e.message);
    }
}

// ---- the layout script (a layout reset, fusion-config.sh's rebuild, the Global Theme's layout)
test("layout: a fresh HOME gets a top bar on every screen, adaptive, and no glass keys", () => {
    const s = shell({ screens: TWO, files: rc() });
    s.run(LAYOUT);
    assert.strictEqual(tops(s).length, 2);
    assert.deepStrictEqual(tops(s).map((p) => p.opacity), ["adaptive", "adaptive"]);
    assert.strictEqual(docks(s)[0].opacity, "translucent");
    assert.strictEqual(all(s, "org.plasmafusion.quicksettings").length, 2);
    for (const t of ["org.plasmafusion.quicksettings", "org.plasmafusion.dock", "org.plasmafusion.launcher", "org.plasmafusion.systemcard"])
        assert.ok(all(s, t).every((w) => glass(w) === undefined), t);
});

test("layout: \"Top bar on every screen\" off gives only the main screen a top bar", () => {
    const s = shell({ screens: TWO, files: rc({ EveryScreen: "false" }) });
    s.run(LAYOUT);
    assert.strictEqual(tops(s).length, 1, "top bars: " + tops(s).length);
    assert.ok(has(tops(s)[0], "org.plasmafusion.quicksettings"));
    assert.ok(has(tops(s)[0], "org.kde.plasma.systemtray"));
});

test("layout: Glass Solid reaches every new widget with a glass key", () => {
    const s = shell({ screens: TWO, files: rc(null, { Glass: "Solid" }) });
    s.run(LAYOUT);
    for (const t of ["org.plasmafusion.quicksettings", "org.plasmafusion.dock", "org.plasmafusion.launcher", "org.plasmafusion.systemcard"]) {
        assert.ok(all(s, t).length > 0, t + " is in the layout");
        assert.ok(all(s, t).every((w) => glass(w) === "solid"), t + ": " + all(s, t).map(glass));
    }
    assert.deepStrictEqual(tops(s).map((p) => p.opacity), ["adaptive", "adaptive"], "Solid glass keeps the adaptive bar");
});

test("layout: Glass Reduced makes the bars and the dock opaque", () => {
    const s = shell({ screens: TWO, files: rc({ SolidNextToWindows: "false" }, { Glass: "Reduced" }) });
    s.run(LAYOUT);
    assert.deepStrictEqual(tops(s).map((p) => p.opacity), ["opaque", "opaque"]);
    assert.strictEqual(docks(s)[0].opacity, "opaque");
    assert.ok(all(s, "org.plasmafusion.quicksettings").every((w) => glass(w) === "reduced"));
});

test("layout: \"Solid top bar next to windows\" off makes the bars translucent", () => {
    const s = shell({ screens: TWO, files: rc({ SolidNextToWindows: "false" }, { Glass: "Full" }) });
    s.run(LAYOUT);
    assert.deepStrictEqual(tops(s).map((p) => p.opacity), ["translucent", "translucent"]);
    assert.strictEqual(docks(s)[0].opacity, "translucent");
    assert.ok(all(s, "org.plasmafusion.quicksettings").every((w) => glass(w) === undefined), "Full writes no key");
});

// ---- ensure-topbars.js (a screen connected later; --screens; the settings page)
function mainBar() {
    return { id: 2, type: "org.kde.panel", screen: 0, location: "top", opacity: "adaptive", config: {}, widgets: [
        { id: 3, type: "org.plasmafusion.appname", config: {} },
        { id: 6, type: "org.kde.plasma.systemtray", config: { General: { hiddenItems: ["org.kde.kscreen"] } } },
        { id: 8, type: "org.plasmafusion.quicksettings", config: { General: { glass: "solid" } } }] };
}
function screenTwo(files) {
    const s = shell({ screens: TWO, files: files, panels: [mainBar()] });
    s.run(ENSURE);
    const bar = tops(s).find((p) => p.screen === 1);
    assert.ok(bar, "a bar on the second screen: " + s.output);
    return { s, bar, qs: bar.widgets.find((w) => w.type === "org.plasmafusion.quicksettings") };
}

test("ensure-topbars: a new screen's bar with the page's defaults is adaptive", () => {
    const { bar, qs } = screenTwo(rc());
    assert.strictEqual(bar.opacity, "adaptive");
    assert.ok(qs, "quick settings in the new bar");
    assert.strictEqual(glass(qs), undefined);
});

test("ensure-topbars: with Glass Solid the new bar's quick settings is solid", () => {
    const { bar, qs } = screenTwo(rc(null, { Glass: "Solid" }));
    assert.strictEqual(glass(qs), "solid");
    assert.strictEqual(bar.opacity, "adaptive");
});

test("ensure-topbars: with Glass Reduced the new bar is opaque", () => {
    const { bar, qs } = screenTwo(rc(null, { Glass: "Reduced" }));
    assert.strictEqual(bar.opacity, "opaque");
    assert.strictEqual(glass(qs), "reduced");
});

test("ensure-topbars: with \"Solid top bar next to windows\" off the new bar is translucent", () => {
    const { bar } = screenTwo(rc({ SolidNextToWindows: "false" }));
    assert.strictEqual(bar.opacity, "translucent");
});

// The system meters switch is on (the settings page reads it from the main bar, which has them):
// a bar made or completed later gets them right before quick settings, as the page places them.
function withMeters(bar) {
    bar.widgets.splice(2, 0, { id: 7, type: "org.plasmafusion.meters", config: {} });
    return bar;
}
const types = (p) => p.widgets.map((w) => w.type);
test("ensure-topbars: with the main bar's meters on, a new screen's bar gets them before quick settings", () => {
    const s = shell({ screens: TWO, files: rc(), panels: [withMeters(mainBar())] });
    s.run(ENSURE);
    const bar = tops(s).find((p) => p.screen === 1);
    const t = types(bar);
    assert.ok(t.includes("org.plasmafusion.meters"), "meters in the new bar: " + t.join(" "));
    assert.strictEqual(t.indexOf("org.plasmafusion.meters"), t.indexOf("org.plasmafusion.quicksettings") - 1, t.join(" "));
});
test("ensure-topbars: with the main bar's meters on, an older bar completed later gets them too", () => {
    const old = { id: 20, type: "org.kde.panel", screen: 1, location: "top", opacity: "adaptive", config: {}, widgets: [
        { id: 21, type: "org.plasmafusion.appname", config: {} },
        { id: 22, type: "org.plasmafusion.clockpill", config: {} }] };
    const s = shell({ screens: TWO, files: rc(), panels: [withMeters(mainBar()), old] });
    s.run(ENSURE);
    const t = types(tops(s).find((p) => p.id === 20));
    assert.deepStrictEqual(t.slice(2), ["org.kde.plasma.systemtray", "org.plasmafusion.meters", "org.plasmafusion.quicksettings"]);
    assert.match(s.output, /completed 1/);
});
test("ensure-topbars: without meters in the main bar a new bar gets none", () => {
    const { bar } = screenTwo(rc());
    assert.ok(!has(bar, "org.plasmafusion.meters"));
});

// The live chips (LiveChips board): right before the tray, which hides the items they replace.
const CHIPS = "org.plasmafusion.livechips";
const CHIPS_ITEMS = ["plasmashell_microphone", "org.kde.plasma.cameraindicator", "xdg-desktop-portal-kde", "Spectacle"];
const trayOff = (bar) => {
    const g = (bar.widgets.find((w) => w.type === "org.kde.plasma.systemtray").config || {}).General || {};
    return { hidden: g.hiddenItems || [], disabled: g.disabledStatusNotifiers || [] };
};
test("layout: the live chips sit right before the tray, whose items they replace are hidden", () => {
    const s = shell({ screens: TWO, files: rc() });
    s.run(LAYOUT);
    for (const bar of tops(s)) {
        const t = types(bar);
        assert.strictEqual(t.indexOf(CHIPS), t.indexOf("org.kde.plasma.systemtray") - 1, "screen " + bar.screen + ": " + t.join(" "));
        const off = trayOff(bar);
        for (const id of CHIPS_ITEMS) {
            assert.ok(off.hidden.includes(id) && off.disabled.includes(id), id + " hidden on screen " + bar.screen);
        }
    }
});
test("layout: without the live chips installed the tray keeps their items", () => {
    const s = shell({ screens: TWO, files: rc(), without: [CHIPS] });
    s.run(LAYOUT);
    for (const bar of tops(s)) {
        assert.ok(!has(bar, CHIPS));
        const off = trayOff(bar);
        assert.ok(CHIPS_ITEMS.every((id) => !off.hidden.includes(id) && !off.disabled.includes(id)), JSON.stringify(off));
        assert.ok(off.hidden.includes("org.kde.plasma.volume"), "the other lists as before");
    }
});
function withChips(bar) {
    const at = bar.widgets.findIndex((w) => w.type === "org.kde.plasma.systemtray");
    bar.widgets.splice(at, 0, { id: 9, type: CHIPS, config: {} });
    return bar;
}
test("ensure-topbars: with the main bar's chips, a new screen's bar gets them right before its tray", () => {
    const s = shell({ screens: TWO, files: rc(), panels: [withChips(mainBar())] });
    s.run(ENSURE);
    const t = types(tops(s).find((p) => p.screen === 1));
    assert.strictEqual(t.indexOf(CHIPS), t.indexOf("org.kde.plasma.systemtray") - 1, t.join(" "));
});
test("ensure-topbars: the tray copied from the main bar hides the chips' items, which that tray shows", () => {
    // The main tray hides only one item of the user's: none of those the chips replace.
    const s = shell({ screens: TWO, files: rc(), panels: [withChips(mainBar())] });
    s.run(ENSURE);
    const off = trayOff(tops(s).find((p) => p.screen === 1));
    assert.ok(off.hidden.includes("org.kde.kscreen"), "the main tray's list is copied: " + JSON.stringify(off));
    assert.ok(CHIPS_ITEMS.every((id) => off.hidden.includes(id) && off.disabled.includes(id)), JSON.stringify(off));
});
test("ensure-topbars: without chips in the main bar the copied tray is as the main one", () => {
    const { bar } = screenTwo(rc());
    assert.deepStrictEqual(trayOff(bar), { hidden: ["org.kde.kscreen"], disabled: [] });
});
test("ensure-topbars: an older bar with a tray of its own gets the chips at the tray's place", () => {
    const old = { id: 20, type: "org.kde.panel", screen: 1, location: "top", opacity: "adaptive", config: {}, widgets: [
        { id: 21, type: "org.plasmafusion.appname", config: {} },
        { id: 22, type: "org.plasmafusion.clockpill", config: {} },
        { id: 23, type: "org.kde.plasma.systemtray", config: {} }] };
    const s = shell({ screens: TWO, files: rc(), panels: [withChips(mainBar()), old] });
    s.run(ENSURE);
    const bar = tops(s).find((p) => p.id === 20);
    assert.deepStrictEqual(types(bar), ["org.plasmafusion.appname", "org.plasmafusion.clockpill", CHIPS, "org.kde.plasma.systemtray",
                                        "org.plasmafusion.quicksettings"]);
    // That tray hides the items the chips replace too.
    const off = trayOff(bar);
    assert.ok(CHIPS_ITEMS.every((id) => off.hidden.includes(id) && off.disabled.includes(id)), JSON.stringify(off));
});
test("ensure-topbars: without chips in the main bar a new bar gets none", () => {
    const { bar } = screenTwo(rc());
    assert.ok(!has(bar, CHIPS));
});
test("ensure-topbars: a first bar (no main bar) gets the chips and a tray that hides their items", () => {
    // Every top bar removed, the dock left.
    const dock = { id: 30, type: "org.kde.panel", screen: 0, location: "bottom", opacity: "translucent", config: {}, widgets: [] };
    const s = shell({ screens: [[1920, 1080]], files: rc(), panels: [dock] });
    s.run(ENSURE);
    const bar = tops(s)[0];
    assert.ok(bar, s.output);
    const t = types(bar);
    assert.strictEqual(t.indexOf(CHIPS), t.indexOf("org.kde.plasma.systemtray") - 1, t.join(" "));
    assert.ok(CHIPS_ITEMS.every((id) => trayOff(bar).hidden.includes(id)), JSON.stringify(trayOff(bar)));
});
test("ensure-topbars: with two screens and no bar, the second screen's bar gets the chips of the first", () => {
    const dock = { id: 30, type: "org.kde.panel", screen: 0, location: "bottom", opacity: "translucent", config: {}, widgets: [] };
    const s = shell({ screens: TWO, files: rc(), panels: [dock] });
    s.run(ENSURE);
    assert.strictEqual(tops(s).length, 2, s.output);
    for (const bar of tops(s)) {
        const t = types(bar);
        assert.strictEqual(t.indexOf(CHIPS), t.indexOf("org.kde.plasma.systemtray") - 1, "screen " + bar.screen + ": " + t.join(" "));
        assert.ok(CHIPS_ITEMS.every((id) => trayOff(bar).hidden.includes(id)), "screen " + bar.screen + ": " + JSON.stringify(trayOff(bar)));
    }
});

// A dock on every screen (plasmafusionrc [Dock] EveryScreen=true): the second screen's dock follows
// the main one.
function dockPanel(opts) {
    return { id: 40, type: "org.kde.panel", screen: 0, location: "bottom", height: 72, hiding: "dodgewindows", opacity: "translucent",
             config: {}, widgets: [
        { id: 41, type: "org.plasmafusion.launcher", config: { General: { buttonStyle: "hidden", favoritesPortedToKAstats: true, glass: "solid",
                                                                           showRecommended: false, openRequest: "home:1" } } },
        { id: 42, type: "org.plasmafusion.dock", config: { General: Object.assign({ launchers: ["applications:a.desktop", "applications:b.desktop"],
                                                                                   magnifiedSize: 56, debugAction: "menu:1" }, opts || {}) } }] };
}
const docksOf = (s) => s.panels.filter((p) => p.widgets.some((w) => w.type === "org.plasmafusion.dock"));
const general = (w) => (w.config || {}).General || {};
const dockRc = (v) => { const f = rc(); f.plasmafusionrc.Dock = { EveryScreen: v }; return f; };
test("ensure-topbars: a dock on every screen gives the second screen a dock like the main one", () => {
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), dockPanel()] });
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 1/, s.output);
    const added = docksOf(s).find((p) => p.screen === 1);
    assert.ok(added, "a dock panel on screen 1");
    assert.deepStrictEqual([added.location, added.height, added.hiding, added.opacity, added.floating, added.lengthMode, added.alignment],
                           ["bottom", 72, "dodgewindows", "translucent", true, "fit", "center"]);
    assert.deepStrictEqual(added.widgets.map((w) => w.type), ["org.plasmafusion.launcher", "org.plasmafusion.dock"], "its own launcher first");
    const d = general(added.widgets[1]), l = general(added.widgets[0]);
    assert.deepStrictEqual(d.launchers, ["applications:a.desktop", "applications:b.desktop"], "the pins, as a list");
    assert.strictEqual(d.magnifiedSize, 56);
    assert.strictEqual(d.debugAction, undefined, "a test hook is not copied");
    assert.strictEqual(d.showOnlyCurrentScreen, true, "it lists its own screen's windows");
    assert.deepStrictEqual([l.buttonStyle, l.glass, l.showRecommended, l.favoritesPortedToKAstats, l.openRequest],
                           ["hidden", "solid", false, true, undefined], "the launcher: hidden, the main one's settings, no request");
    const main = docksOf(s).find((p) => p.id === 40).widgets[1];
    assert.strictEqual(general(main).showOnlyCurrentScreen, true, "the main dock too");
    assert.strictEqual(main.config.PlasmaFusion.onlyCurrentScreenBefore, false, "  remembering what it had");
    assert.strictEqual(added.widgets[1].config.PlasmaFusion.everyScreenCopy, true, "the new dock is marked as a copy");
    assert.strictEqual(main.config.PlasmaFusion.everyScreenCopy, undefined, "  the main one is not");
});
test("ensure-topbars: without [Dock] EveryScreen there is one dock", () => {
    const s = shell({ screens: TWO, files: rc(), panels: [mainBar(), dockPanel()] });
    s.run(ENSURE);
    assert.match(s.output, /docks: one/);
    assert.strictEqual(docksOf(s).length, 1);
    assert.strictEqual(general(docksOf(s)[0].widgets[1]).showOnlyCurrentScreen, undefined, "the main dock is left as it is");
});
test("ensure-topbars: a dock on every screen, run again: nothing more, the remembered value kept", () => {
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), dockPanel({ showOnlyCurrentScreen: true })] });
    s.run(ENSURE);
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 0/, s.output);
    assert.strictEqual(docksOf(s).length, 2, "one dock per screen");
    const main = docksOf(s).find((p) => p.id === 40).widgets[1];
    assert.strictEqual(main.config.PlasmaFusion.onlyCurrentScreenBefore, true, "a main dock that showed its own screen only remembers that");
});
test("ensure-topbars: a dock only on the second screen: it stays the main one, the new one is a copy", () => {
    // The settings page removes only the copies when the switch goes off, so the dock there was
    // stays, with the value it remembers.
    const p = dockPanel();
    p.screen = 1;
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), p] });
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 1$/m, s.output);
    const dockOf = (panel) => panel.widgets.find((w) => w.type === "org.plasmafusion.dock");
    const pf = (w) => (w.config || {}).PlasmaFusion || {};
    const first = dockOf(docksOf(s).find((d) => d.screen === 0)), second = dockOf(docksOf(s).find((d) => d.id === 40));
    assert.deepStrictEqual([pf(first).everyScreenCopy, pf(first).onlyCurrentScreenBefore], [true, undefined],
                           "the new dock on screen 0: a copy, nothing remembered");
    assert.deepStrictEqual([pf(second).everyScreenCopy, pf(second).onlyCurrentScreenBefore], [undefined, false],
                           "the dock on screen 1: no copy, remembers false");
    assert.strictEqual(general(first).magnifiedSize, 56, "the copy has the original's settings");
    assert.deepStrictEqual([general(first).showOnlyCurrentScreen, general(second).showOnlyCurrentScreen], [true, true], "both list their own screen");
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 0/, s.output);
    assert.deepStrictEqual([pf(first).onlyCurrentScreenBefore, pf(second).onlyCurrentScreenBefore], [undefined, false], "run again: the same");
});
test("ensure-topbars: a copy takes the main dock's edge (board DockPosition.dc.html)", () => {
    const left = dockPanel();
    left.location = "left";
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), left] });
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 1$/m, s.output);
    const copy = docksOf(s).find((d) => d.screen === 1);
    assert.ok(copy, "a dock for screen 1");
    assert.strictEqual(copy.location, "left", "on the left, as the main dock");
});
test("ensure-topbars: a second dock of the user's on the main screen: no copy made for it, it remembers too", () => {
    const own = dockPanel({ showOnlyCurrentScreen: true });
    own.id = 50;
    own.widgets = own.widgets.map((w, i) => Object.assign({}, w, { id: 51 + i }));
    own.location = "left";
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), dockPanel(), own] });
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 1$/m, s.output);
    assert.strictEqual(docksOf(s).length, 3, "the two of screen 0 and one copy for screen 1");
    const ownDock = docksOf(s).find((d) => d.id === 50).widgets.find((w) => w.type === "org.plasmafusion.dock");
    assert.deepStrictEqual([general(ownDock).showOnlyCurrentScreen, ownDock.config.PlasmaFusion.onlyCurrentScreenBefore], [true, true],
                           "the user's dock lists its own screen and remembers it already did");
    assert.strictEqual((ownDock.config.PlasmaFusion || {}).everyScreenCopy, undefined, "it is not a copy");
});
test("ensure-topbars: a dock the shell cannot make leaves no panel behind", () => {
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), dockPanel()], failAdd: ["org.plasmafusion.dock"] });
    const bottom = () => s.panels.filter((p) => p.location === "bottom").map((p) => p.screen);
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 0, not made 1/, s.output);
    assert.deepStrictEqual(bottom(), [0], "no new dock panel (nor its launcher) on screen 1");
    s.run(ENSURE);
    assert.deepStrictEqual(bottom(), [0], "a second run neither");
});
test("ensure-topbars: a launcher the shell cannot make leaves no panel behind either", () => {
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), dockPanel()], failAdd: ["org.plasmafusion.launcher"] });
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 0, not made 1/, s.output);
    assert.deepStrictEqual(s.panels.filter((p) => p.location === "bottom").map((p) => p.screen), [0], "no dock without its launcher on screen 1");
});
const dockOf = (panel) => panel.widgets.find((w) => w.type === "org.plasmafusion.dock");
const launcherOf = (panel) => panel.widgets.find((w) => w.type === "org.plasmafusion.launcher");
test("ensure-topbars: while the power service holds a key, a copy gets the user's value", () => {
    const f = dockRc("true");
    f.plasmafusionrc.Power = { UserWidgetValues: "42/magnify=true,42/glass=full,41/glass=full" };
    const s = shell({ screens: TWO, files: f, panels: [mainBar(), dockPanel({ magnify: false, glass: "solid" })] });
    s.run(ENSURE);
    const copy = docksOf(s).find((p) => p.screen === 1);
    assert.deepStrictEqual([general(dockOf(copy)).magnify, general(dockOf(copy)).glass, general(launcherOf(copy)).glass], [true, "full", "full"],
                           "the user's magnification and glass, not the held ones");
});
test("ensure-topbars: a copy's panel whose dock the user removed still counts for its screen", () => {
    const left = { id: 60, type: "org.kde.panel", screen: 1, location: "bottom", config: { PlasmaFusion: { everyScreenCopy: true } },
                   widgets: [{ id: 61, type: "org.plasmafusion.launcher", config: {} }] };
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), dockPanel(), left] });
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 0$/m, s.output);
    assert.deepStrictEqual(s.panels.filter((p) => p.location === "bottom").map((p) => p.id), [40, 60], "no second panel for screen 1");
});
test("ensure-topbars: a dock panel of a screen that is not there is left as it is, the others are filled", () => {
    const gone = dockPanel();
    gone.id = 70;
    gone.screen = 2;
    gone.widgets = gone.widgets.map((w, i) => Object.assign({}, w, { id: 71 + i, config: { General: {} } }));
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), dockPanel(), gone] });
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 1, 1 of a screen not there left as they are/, s.output);
    assert.ok(docksOf(s).some((p) => p.screen === 1), "screen 1 gets its dock");
    assert.deepStrictEqual(general(dockOf(docksOf(s).find((p) => p.id === 70))), {}, "the one of screen 2 is not touched");
});
test("ensure-topbars: without the launcher installed no copy is made", () => {
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), dockPanel()], without: ["org.plasmafusion.launcher"] });
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 0, not made 1/, s.output);
    assert.deepStrictEqual(s.panels.filter((p) => p.location === "bottom").map((p) => p.screen), [0]);
});
test("ensure-topbars: a main dock without a launcher of its own still gives each copy one", () => {
    const p = dockPanel();
    p.widgets = p.widgets.filter((w) => w.type !== "org.plasmafusion.launcher");
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), p] });
    s.run(ENSURE);
    const copy = docksOf(s).find((d) => d.screen === 1);
    assert.ok(copy && launcherOf(copy), "the copy has its launcher");
    assert.strictEqual(general(launcherOf(copy)).buttonStyle, "hidden");
    assert.strictEqual(copy.config.PlasmaFusion.everyScreenCopy, true, "and its panel is marked as a copy");
});
// The settings page kept a copy as the one dock (standInFor) while the dock there was sat on an
// unplugged screen; the switch is off now.
function standIn(origScreen) {
    const keep = dockPanel();
    keep.id = 80;
    keep.config = { PlasmaFusion: { standInFor: "70" } };
    keep.widgets = keep.widgets.map((w, i) => Object.assign({}, w, { id: 81 + i }));
    const orig = dockPanel();
    orig.id = 70;
    orig.screen = origScreen;
    orig.widgets = orig.widgets.map((w, i) => Object.assign({}, w, { id: 71 + i }));
    return shell({ screens: TWO, files: dockRc("false"), panels: [mainBar(), keep, orig] });
}
test("ensure-topbars: switch off, the dock a copy stood in for is back on a screen: the stand-in goes", () => {
    const s = standIn(1);
    s.run(ENSURE);
    assert.match(s.output, /docks: one .*, 1 stand-in gave way/, s.output);
    assert.deepStrictEqual(docksOf(s).map((p) => p.id), [70], "only the dock there was");
});
test("ensure-topbars: switch off, that dock still on an unplugged screen: the stand-in stays", () => {
    const s = standIn(2);
    s.run(ENSURE);
    assert.deepStrictEqual(docksOf(s).map((p) => p.id).sort(), [70, 80]);
    assert.strictEqual(s.panels.find((p) => p.id === 80).config.PlasmaFusion.standInFor, "70", "still standing in");
});
test("ensure-topbars: switch off, that dock removed: the stand-in is the dock now", () => {
    const s = standIn(1);
    s.panels.splice(s.panels.findIndex((p) => p.id === 70), 1);
    s.run(ENSURE);
    assert.deepStrictEqual(docksOf(s).map((p) => p.id), [80]);
    assert.strictEqual(s.panels.find((p) => p.id === 80).config.PlasmaFusion.standInFor, "", "no longer standing in");
});
test("ensure-topbars: the only dock not on a screen yet (the session's start): asked again", () => {
    const p = dockPanel();
    p.screen = 2;
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), p] });
    s.run(ENSURE);
    assert.match(s.output, /docks: skipped, 1 dock panel\(s\) without a screen yet/, s.output);
    assert.deepStrictEqual(docksOf(s).map((d) => d.id), [40], "no dock made from it");
});
test("ensure-topbars: no dock installed, no docks", () => {
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), dockPanel()], without: ["org.plasmafusion.dock"] });
    s.run(ENSURE);
    assert.match(s.output, /docks: the Plasma Fusion dock is not installed/);
});

test("ensure-topbars: \"Top bar on every screen\" off adds nothing", () => {
    const s = shell({ screens: TWO, files: rc({ EveryScreen: "false" }), panels: [mainBar()] });
    s.run(ENSURE);
    assert.strictEqual(tops(s).length, 1);
    assert.match(s.output, /top bars: off/);
});

// ---- the settings file's layout: export-layout.js and import-layout.js
const EXPORT = fs.readFileSync(path.join(dir, "export-layout.js"), "utf8");
const IMPORT = fs.readFileSync(path.join(dir, "import-layout.js"), "utf8");
const exported = (s) => JSON.parse(s.run(EXPORT).trim().split("\n").pop());
// A bar and a dock with what the export must carry: a list, a subgroup, a one-time request, a
// shortcut; a copy "Dock on every screen" made; a panel of a screen that is not there.
function transferLayout() {
    const bar = mainBar();
    bar.widgets[0].shortcut = "Meta+A";
    // The bar's own marks and Plasma's keys of the panel (its top group, its widgets' order).
    bar.config = { "": { plugin: "org.kde.panel", lastScreen: 0, formfactor: 2, immutability: 1 },
                   General: { AppletOrder: "3;6;8" }, PlasmaFusion: { statusItems: true, standInFor: "12" } };
    // The tray's own items are listed by its [General] lists; its [Applets] are left out.
    bar.widgets[1].config["Applets][61"] = { plugin: "org.kde.plasma.battery" };
    bar.widgets[1].config[""] = { SystrayContainmentId: 7, PreloadWeight: 42 };
    const dock = dockPanel();
    dock.widgets[1].config["General][Pins"] = { order: "a,b" };
    Object.assign(dock, { lengthMode: "custom", offset: 10, length: 800, minimumLength: 600, maximumLength: 900 });
    const copy = { id: 90, type: "org.kde.panel", screen: 1, location: "bottom", config: { PlasmaFusion: { everyScreenCopy: true } },
                   widgets: [{ id: 91, type: "org.plasmafusion.dock", config: { PlasmaFusion: { everyScreenCopy: true } } }] };
    const gone = { id: 95, type: "org.kde.panel", screen: 5, location: "left", config: {}, widgets: [{ id: 96, type: "org.plasmafusion.dock", config: {} }] };
    return [bar, dock, copy, gone];
}
test("export-layout: the panels with their screens, widgets in order, every config group; copies and missing screens left out", () => {
    const s = shell({ screens: TWO, files: rc(), panels: transferLayout() });
    s.files.plasmashellrc = { "PlasmaViews][Panel 2": { floatingApplets: "1" } };
    const out = exported(s);
    assert.strictEqual(out.version, 1);
    assert.deepStrictEqual(out.panels.map((p) => [p.screen, p.location]), [[0, "top"], [0, "bottom"]], "the bar and the dock, not the copy nor the other screen's");
    assert.deepStrictEqual(out.left, ["copy", "screen"]);
    const dock = out.panels[1];
    assert.deepStrictEqual(dock.widgets.map((w) => w.type), ["org.plasmafusion.launcher", "org.plasmafusion.dock"], "in the panel's order");
    const groups = dock.widgets[1].config.map((g) => g.group.join("/"));
    assert.deepStrictEqual(groups.sort(), ["General", "General/Pins"]);
    const general = dock.widgets[1].config.find((g) => g.group.join("/") === "General").keys;
    assert.strictEqual(general.launchers, "applications:a.desktop,applications:b.desktop", "a list as its text");
    assert.strictEqual(general.debugAction, undefined, "a one-time request is not exported");
    assert.strictEqual(out.panels[0].widgets[0].shortcut, "Meta+A", "the shortcut");
    assert.deepStrictEqual([dock.height, dock.hiding, dock.opacity], [72, "dodgewindows", "translucent"], "the panel's look");
    assert.deepStrictEqual([dock.offset, dock.length, dock.minimumLength, dock.maximumLength], [10, 800, 600, 900], "a custom length");
    assert.strictEqual(out.panels[0].offset, undefined, "only with a custom length");
    assert.deepStrictEqual([out.panels[0].floatingApplets, dock.floatingApplets], [true, false], "the panel view's floatingApplets");
    assert.deepStrictEqual(out.panels[0].config, [{ group: [], keys: { immutability: "1" } }, { group: ["PlasmaFusion"], keys: { statusItems: "true" } }],
                           "the bar's own configuration, without what names its screen, place, plugin, widgets or other panels");
    const tray = out.panels[0].widgets[1].config;
    assert.deepStrictEqual(tray, [{ group: [], keys: { PreloadWeight: "42" } }, { group: ["General"], keys: { hiddenItems: "org.kde.kscreen" } }],
                           "the tray's lists, not its [Applets] nor the id of a containment");
});
test("import-layout: the file's panels take the place of the ones there are, and export the same again", () => {
    const from = shell({ screens: TWO, files: rc(), panels: transferLayout() });
    from.files.plasmashellrc = { "PlasmaViews][Panel 2": { floatingApplets: "1" } };
    const file = exported(from);
    assert.ok(file.panels[0].floatingApplets);
    const to = shell({ screens: TWO, files: rc(), panels: [dockPanel()] });
    const out = JSON.parse(to.run("var LAYOUT = " + JSON.stringify(file) + ";\n" + IMPORT).trim().split("\n").pop());
    assert.deepStrictEqual([out.panels, out.leftOut, out.notInstalled], [2, 0, []], JSON.stringify(out));
    const again = exported(to);
    const strip = (l) => l.panels.map((p) => Object.assign({}, p, { widgets: p.widgets.map((w) => Object.assign({}, w, { shortcut: "" })) }));
    assert.deepStrictEqual(strip(again), strip(file), "the same panels, widgets and configuration (the page gives the shortcuts)");
    assert.ok(!to.panels.some((p) => p.id === 40), "the panel there was is gone");
});
test("export-layout: while the power service holds a key the user's value is taken, the power tier not at all", () => {
    const f = rc();
    f.plasmafusionrc.Power = { UserWidgetValues: "42/magnify=true,42/glass=full" };
    const s = shell({ screens: TWO, files: f, panels: [dockPanel({ magnify: false, glass: "solid", powerTier: 2 })] });
    const keys = exported(s).panels[0].widgets[1].config.find((g) => g.group.join("/") === "General").keys;
    assert.deepStrictEqual([keys.magnify, keys.glass, keys.powerTier], ["true", "full", undefined]);
});
test("export-layout: with the main dock on a monitor that is unplugged, the lowest copy is taken as the dock", () => {
    const gone = dockPanel();
    gone.screen = 5;
    const copy = (id, screen) => ({ id, type: "org.kde.panel", screen, location: "bottom", config: { PlasmaFusion: { everyScreenCopy: true } },
                                    widgets: [{ id: id + 1, type: "org.plasmafusion.launcher", config: {} },
                                              { id: id + 2, type: "org.plasmafusion.dock",
                                                config: { General: { showOnlyCurrentScreen: true, magnifiedSize: 56 }, PlasmaFusion: { everyScreenCopy: true } } }] });
    const s = shell({ screens: TWO, files: rc(), panels: [mainBar(), gone, copy(80, 1), copy(70, 0)] });
    const out = exported(s);
    assert.deepStrictEqual(out.panels.map((p) => [p.screen, p.location]), [[0, "top"], [0, "bottom"]], "the bar and the copy of screen 0");
    assert.deepStrictEqual(out.left, ["screen", "copy"]);
    const dock = out.panels[1].widgets[1].config;
    assert.deepStrictEqual(dock.map((g) => g.group.join("/")), ["General"], "no copy mark");
    assert.deepStrictEqual(dock[0].keys, { showOnlyCurrentScreen: "false", magnifiedSize: "56" }, "every screen's windows");
});
test("import-layout: a panel of a screen not here goes to the first screen when that edge is free there, else it is left out", () => {
    const file = exported(shell({ screens: TWO, files: rc(), panels: transferLayout() }));
    file.panels[1].screen = 1;
    file.panels.push(Object.assign({}, file.panels[0], { screen: 1 }));
    file.panels[0].widgets.push({ type: "org.example.notinstalled", shortcut: "", config: [] });
    const to = shell({ screens: [[1920, 1080]], files: rc(), panels: [] });
    const out = JSON.parse(to.run("var LAYOUT = " + JSON.stringify(file) + ";\n" + IMPORT).trim().split("\n").pop());
    assert.deepStrictEqual([out.panels, out.leftOut, out.notInstalled], [2, 1, ["org.example.notinstalled"]], JSON.stringify(out));
    assert.deepStrictEqual(to.panels.map((p) => [p.screen, p.location]), [[0, "top"], [0, "bottom"]], "the dock on the first screen, one bar");
});
test("import-layout: the keys the file gives, by the new widget's id (two widgets of one type keep their own)", () => {
    const file = exported(shell({ screens: TWO, files: rc(), panels: transferLayout() }));
    const bar = file.panels[0];
    const qs = bar.widgets.find((w) => w.type === "org.plasmafusion.quicksettings");
    bar.widgets.push(Object.assign({}, qs, { shortcut: "Meta+W" }));
    qs.shortcut = "Meta+Q";
    const to = shell({ screens: TWO, files: rc(), panels: [] });
    const out = JSON.parse(to.run("var LAYOUT = " + JSON.stringify(file) + ";\n" + IMPORT).trim().split("\n").pop());
    const made = to.panels.find((p) => p.location === "top").widgets.filter((w) => w.type === "org.plasmafusion.quicksettings").map((w) => w.id);
    assert.strictEqual(made.length, 2);
    assert.deepStrictEqual(out.keys.filter((k) => k.type === "org.plasmafusion.quicksettings"),
                           [{ id: made[0], type: "org.plasmafusion.quicksettings", key: "Meta+Q" },
                            { id: made[1], type: "org.plasmafusion.quicksettings", key: "Meta+W" }]);
    assert.ok(out.keys.every((k) => k.key !== ""), "no entry for a widget without a key");
    assert.strictEqual(out.keys.length, 3, "Meta+A of the app name too: " + JSON.stringify(out.keys));
});
test("import-layout: PHASE remove only removes the panels there are, add only adds the file's", () => {
    const file = exported(shell({ screens: TWO, files: rc(), panels: transferLayout() }));
    const to = shell({ screens: TWO, files: rc(), panels: [mainBar(), dockPanel()] });
    const removed = JSON.parse(to.run("var LAYOUT = " + JSON.stringify(file) + ";\nvar PHASE = \"remove\";\n" + IMPORT).trim().split("\n").pop());
    assert.deepStrictEqual([removed, to.panels.length], [{ removed: 2 }, 0], "removed, none added");
    to.panels.push(dockPanel());
    const added = JSON.parse(to.run("var LAYOUT = " + JSON.stringify(file) + ";\nvar PHASE = \"add\";\n" + IMPORT).trim().split("\n").pop());
    assert.deepStrictEqual([added.panels, to.panels.length, to.panels[0].id], [2, 3, 40], "added, none removed");
    for (const layout of [{ version: 2, panels: [{ screen: 0, location: "top", widgets: [] }] }, { version: 1, panels: [] }]) {
        const kept = shell({ screens: TWO, files: rc(), panels: [dockPanel()] });
        assert.ok(JSON.parse(kept.run("var LAYOUT = " + JSON.stringify(layout) + ";\nvar PHASE = \"remove\";\n" + IMPORT).trim().split("\n").pop()).error);
        assert.deepStrictEqual(kept.panels.map((p) => p.id), [40], "a file that is not one removes nothing");
    }
});
test("import-layout: no layout of this version, or one without panels: nothing is changed", () => {
    for (const layout of [{ version: 2, panels: [{ screen: 0, location: "top", widgets: [] }] }, { version: 1, panels: [] }, { version: 1 }]) {
        const to = shell({ screens: TWO, files: rc(), panels: [dockPanel()] });
        const out = JSON.parse(to.run("var LAYOUT = " + JSON.stringify(layout) + ";\n" + IMPORT).trim().split("\n").pop());
        assert.ok(out.error, JSON.stringify(out));
        assert.deepStrictEqual(to.panels.map((p) => p.id), [40], "the panel stays");
    }
});

// ---- the Add Panel templates
const TEMPLATES = path.join(__dirname, "..", "layout-templates");
const TOPBAR = fs.readFileSync(path.join(TEMPLATES, "org.plasmafusion.panel.topbar", "contents", "layout.js"), "utf8");
const DOCK = fs.readFileSync(path.join(TEMPLATES, "org.plasmafusion.panel.dock", "contents", "layout.js"), "utf8");

test("Add Panel: the top bar follows Glass Reduced (opaque, quick settings reduced)", () => {
    const s = shell({ screens: TWO, files: rc(null, { Glass: "Reduced" }) });
    s.run(TOPBAR);
    assert.strictEqual(tops(s)[0].opacity, "opaque");
    assert.strictEqual(glass(all(s, "org.plasmafusion.quicksettings")[0]), "reduced");
});

test("Add Panel: the top bar with the page's defaults is adaptive", () => {
    const s = shell({ screens: TWO, files: rc() });
    s.run(TOPBAR);
    assert.strictEqual(tops(s)[0].opacity, "adaptive");
    assert.strictEqual(glass(all(s, "org.plasmafusion.quicksettings")[0]), undefined);
});

test("Add Panel: a top bar that copies another bar's tray hides the items its live chips replace", () => {
    // A bar from before the live chips: its tray hides one item of the user's, and none of theirs.
    const s = shell({ screens: TWO, files: rc(), panels: [mainBar()] });
    s.run(TOPBAR);
    const bar = tops(s).find((p) => p.id !== 2);
    assert.ok(has(bar, CHIPS), types(bar).join(" "));
    const off = trayOff(bar);
    assert.ok(off.hidden.includes("org.kde.kscreen"), "the other tray's list is copied: " + JSON.stringify(off));
    assert.ok(CHIPS_ITEMS.every((id) => off.hidden.includes(id) && off.disabled.includes(id)), JSON.stringify(off));
});

test("Add Panel: without the live chips installed the copied tray is as the other one", () => {
    const s = shell({ screens: TWO, files: rc(), panels: [mainBar()], without: [CHIPS] });
    s.run(TOPBAR);
    const bar = tops(s).find((p) => p.id !== 2);
    assert.ok(!has(bar, CHIPS));
    assert.deepStrictEqual(trayOff(bar), { hidden: ["org.kde.kscreen"], disabled: [] });
});

test("Add Panel: the dock and its launcher follow Glass Solid", () => {
    const s = shell({ screens: TWO, files: rc(null, { Glass: "Solid" }) });
    s.run(DOCK);
    assert.strictEqual(docks(s)[0].opacity, "translucent");
    assert.strictEqual(glass(all(s, "org.plasmafusion.dock")[0]), "solid");
    assert.strictEqual(glass(all(s, "org.plasmafusion.launcher")[0]), "solid");
});

console.log(failed ? `${failed} of ${n} failed` : `all ${n} passed`);
process.exit(failed ? 1 : 0);
