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
test("ensure-topbars: a dock only on the second screen: the one added on the first remembers", () => {
    // The settings page keeps the dock on the lowest screen when the switch goes off (and puts its
    // remembered value back), so the dock added on screen 0 holds what the one there was had.
    const p = dockPanel();
    p.screen = 1;
    const s = shell({ screens: TWO, files: dockRc("true"), panels: [mainBar(), p] });
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 1/, s.output);
    const dockOf = (panel) => panel.widgets.find((w) => w.type === "org.plasmafusion.dock");
    const first = dockOf(docksOf(s).find((d) => d.screen === 0)), second = dockOf(docksOf(s).find((d) => d.id === 40));
    assert.strictEqual(((first.config || {}).PlasmaFusion || {}).onlyCurrentScreenBefore, false, "the new dock on screen 0 remembers false");
    assert.ok(["", undefined].includes(((second.config || {}).PlasmaFusion || {}).onlyCurrentScreenBefore),
              "the dock on screen 1 remembers nothing (it goes when the switch is off)");
    assert.deepStrictEqual([general(first).showOnlyCurrentScreen, general(second).showOnlyCurrentScreen], [true, true], "both list their own screen");
    s.run(ENSURE);
    assert.match(s.output, /docks: screens 2, added 0/, s.output);
    assert.strictEqual(first.config.PlasmaFusion.onlyCurrentScreenBefore, false, "run again: still remembered on screen 0");
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
