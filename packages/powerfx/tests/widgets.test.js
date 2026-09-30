// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The widget script of plasma-fusion-powerfx (its SHELL_JS) against the fake scripting runtime:
// what each tier writes, what it remembers and gives back, and that it never records its own
// values or overwrites a user's change. Run: node packages/powerfx/tests/widgets.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const { run } = require("./fake-shell.js");

const source = fs.readFileSync(path.join(__dirname, "..", "plasma-fusion-powerfx"), "utf8");
const m = source.match(/<<'JS'\n([\s\S]*?)\nJS\n/);
assert(m, "SHELL_JS not found in plasma-fusion-powerfx");
const SHELL_JS = m[1];

// The service's state between calls, as plasmafusionrc [Power] keeps it.
function service(layout) {
    const st = { tier: 0, light: false, map: "" };
    const writes = [];
    function call(apply, tier, light) {
        const pfx = `var PFX = {apply: ${apply}, tier: ${tier}, light: ${light}, prev: ${st.tier}, prevLight: ${st.light}, map: "${st.map}"};\n`;
        const out = run(pfx + SHELL_JS, layout, writes);
        const r = out.match(/^found=(\d+);writes=(\d+);dock=([a-z]*);map=([A-Za-z0-9/=,._-]*)$/);
        assert(r, "bad output: " + out);
        return { found: +r[1], writes: +r[2], dock: r[3], map: r[4] };
    }
    return {
        writes,
        state: st,
        // plan, store, apply: what apply_shell does
        set(tier, light) {
            const plan = call(false, tier, light);
            const before = writes.length;
            if (plan.writes > 0)
                call(true, tier, light);
            assert.strictEqual(writes.length - before, plan.writes, "the plan counted other writes than it made");
            Object.assign(st, { tier, light, map: plan.map });
            return plan;
        },
    };
}

function layout() {
    return {
        desktops: [[
            { id: 30, type: "org.plasmafusion.systemcard", config: { General: { updateInterval: "3000" } } },
            { id: 31, type: "org.plasmafusion.weathercard", config: {} },
            { id: 32, type: "org.kde.plasma.systemmonitor.cpu", config: { Appearance: { updateRateLimit: "2000" } } },
        ]],
        panels: [
            [{ id: 3, type: "org.plasmafusion.appname", config: {} },
             { id: 5, type: "org.plasmafusion.quicksettings", config: {} }],
            [{ id: 12, type: "org.plasmafusion.dock", config: { General: { magnifiedSize: "62" } } },
             { id: 14, type: "org.plasmafusion.launcher", config: { General: { glass: "reduced" } } }],
        ],
    };
}
const W = (l, id) => [...l.desktops.flat(), ...l.panels.flat()].find((w) => w.id === id);
const cfg = (l, id, g, k) => (W(l, id).config[g] || {})[k];

let n = 0;
function test(name, f) { f(); n++; console.log("ok " + n + " " + name); }

test("full on a fresh layout writes nothing", () => {
    const l = layout(), s = service(l);
    const r = s.set(0, true);
    assert.strictEqual(r.found, 3);
    assert.strictEqual(r.writes, 0);
    assert.strictEqual(r.map, "");
    assert.deepStrictEqual(l, layout());
});

test("saver: powerTier 1, monitors x 2, nothing else", () => {
    const l = layout(), s = service(l);
    const r = s.set(1, true);
    assert.strictEqual(cfg(l, 30, "General", "powerTier"), "1");
    assert.strictEqual(cfg(l, 12, "General", "powerTier"), "1");
    assert.strictEqual(cfg(l, 32, "Appearance", "updateRateLimit"), "4000");
    assert.strictEqual(cfg(l, 12, "General", "magnify"), undefined);
    assert.strictEqual(cfg(l, 5, "General", "glass"), undefined);
    assert.strictEqual(r.map, "32/updateRateLimit=2000");
});

test("critical (lighter): powerTier 2, monitors x 4, magnification off, glass solid", () => {
    const l = layout(), s = service(l);
    s.set(1, true);
    const r = s.set(2, true);
    assert.strictEqual(cfg(l, 30, "General", "powerTier"), "2");
    assert.strictEqual(cfg(l, 32, "Appearance", "updateRateLimit"), "8000");
    assert.strictEqual(cfg(l, 12, "General", "magnify"), "false");
    for (const id of [30, 5, 12, 14])
        assert.strictEqual(cfg(l, id, "General", "glass"), "solid", "widget " + id);
    assert.strictEqual(cfg(l, 31, "General", "glass"), undefined, "the weather card has no glass");
    assert.strictEqual(r.dock, "true");
    // the user's values, never the service's
    assert.strictEqual(r.map, "30/glass=full,32/updateRateLimit=2000,5/glass=full,12/magnify=true,12/glass=full,14/glass=reduced");
});

test("back to full gives every value back", () => {
    const l = layout(), s = service(l);
    s.set(2, true);
    const r = s.set(0, true);
    assert.strictEqual(r.map, "");
    assert.strictEqual(cfg(l, 30, "General", "powerTier"), "0");
    assert.strictEqual(cfg(l, 12, "General", "powerTier"), "0");
    assert.strictEqual(cfg(l, 32, "Appearance", "updateRateLimit"), "2000");
    assert.strictEqual(cfg(l, 12, "General", "magnify"), "true");
    assert.strictEqual(cfg(l, 14, "General", "glass"), "reduced");
    assert.strictEqual(cfg(l, 5, "General", "glass"), "full");
    // a second full changes nothing
    assert.strictEqual(s.set(0, true).writes, 0);
});

test("the same tier again writes nothing", () => {
    const l = layout(), s = service(l);
    s.set(2, true);
    const r = s.set(2, true);
    assert.strictEqual(r.writes, 0);
    assert.strictEqual(r.map, s.state.map);
});

test("a change the user made while overridden stays", () => {
    const l = layout(), s = service(l);
    s.set(2, true);
    W(l, 12).config.General.magnify = "true"; // the user turns magnification back on at 8 %
    W(l, 5).config.General.glass = "reduced";
    assert.strictEqual(s.set(2, true).writes, 0, "not overridden again at the same tier");
    s.set(0, true);
    assert.strictEqual(cfg(l, 12, "General", "magnify"), "true");
    assert.strictEqual(cfg(l, 5, "General", "glass"), "reduced");
    assert.strictEqual(cfg(l, 14, "General", "glass"), "reduced");
    assert.strictEqual(s.state.map, "");
});

test("the user's own magnify=false is given back as false", () => {
    const l = layout();
    W(l, 12).config.General.magnify = "false";
    const s = service(l);
    s.set(2, true);
    s.set(0, true);
    assert.strictEqual(cfg(l, 12, "General", "magnify"), "false");
});

test("critical without LighterOnCritical: only the intervals", () => {
    const l = layout(), s = service(l);
    s.set(2, false);
    assert.strictEqual(cfg(l, 12, "General", "magnify"), undefined);
    assert.strictEqual(cfg(l, 5, "General", "glass"), undefined);
    assert.strictEqual(cfg(l, 32, "Appearance", "updateRateLimit"), "8000");
});

test("LighterOnCritical turned off while critical gives glass and magnification back", () => {
    const l = layout(), s = service(l);
    s.set(2, true);
    const r = s.set(2, false);
    assert.strictEqual(cfg(l, 12, "General", "magnify"), "true");
    assert.strictEqual(cfg(l, 14, "General", "glass"), "reduced");
    assert.strictEqual(cfg(l, 32, "Appearance", "updateRateLimit"), "8000");
    assert.strictEqual(r.map, "32/updateRateLimit=2000");
});

test("critical to saver keeps the remembered interval", () => {
    const l = layout(), s = service(l);
    s.set(2, true);
    s.set(1, true);
    assert.strictEqual(cfg(l, 32, "Appearance", "updateRateLimit"), "4000");
    assert.strictEqual(cfg(l, 12, "General", "magnify"), "true");
    s.set(0, true);
    assert.strictEqual(cfg(l, 32, "Appearance", "updateRateLimit"), "2000");
});

test("an unlimited monitor (0) is held at 6 s and 12 s and given back as 0", () => {
    const l = layout();
    W(l, 32).config.Appearance.updateRateLimit = "0";
    const s = service(l);
    s.set(1, true);
    assert.strictEqual(cfg(l, 32, "Appearance", "updateRateLimit"), "6000");
    s.set(2, true);
    assert.strictEqual(cfg(l, 32, "Appearance", "updateRateLimit"), "12000");
    s.set(0, true);
    assert.strictEqual(cfg(l, 32, "Appearance", "updateRateLimit"), "0");
});

test("a widget added while critical (layout reset) is remembered with its own values", () => {
    const l = layout(), s = service(l);
    s.set(2, true);
    l.panels[1].push({ id: 40, type: "org.plasmafusion.dock", config: {} });
    s.set(2, true); // plasmashell came back
    assert.strictEqual(cfg(l, 40, "General", "magnify"), "false");
    assert.ok(s.state.map.includes("40/magnify=true"));
    s.set(0, true);
    assert.strictEqual(cfg(l, 40, "General", "magnify"), "true");
});

test("a value the map cannot hold is left alone", () => {
    const l = layout();
    W(l, 14).config.General.glass = "odd,value";
    const s = service(l);
    s.set(2, true);
    assert.strictEqual(cfg(l, 14, "General", "glass"), "odd,value");
    assert.ok(!s.state.map.includes("14/"));
});

test("plan mode writes nothing", () => {
    const l = layout();
    const pfx = 'var PFX = {apply: false, tier: 2, light: true, prev: 0, prevLight: false, map: ""};\n';
    const writes = [];
    const out = run(pfx + SHELL_JS, l, writes);
    assert.match(out, /writes=[1-9]/);
    assert.strictEqual(writes.length, 0);
    assert.deepStrictEqual(l, layout());
});

test("no layout loaded yet: found=0", () => {
    const pfx = 'var PFX = {apply: false, tier: 2, light: true, prev: 0, prevLight: false, map: ""};\n';
    assert.strictEqual(run(pfx + SHELL_JS, { desktops: [], panels: [] }, []), "found=0;writes=0;dock=;map=");
});

console.log(`all ${n} passed`);
