// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// A stand-in for plasmashell's desktop scripting (plasma-workspace 6.7.5 shell/scripting), enough
// for plasma-fusion-powerfx's widget script and the settings module's scripts (its tests in
// packages/kcm-cpp/tests): desktops(), panels(), knownWidgetTypes, a containment's widgets([TYPE]),
// addWidget, id, type, screen, location and opacity, a widget's id, type, globalShortcut, index and
// remove(), and
// for both currentConfigGroup, readConfig (converted to the default's type, as
// KConfigGroup::readEntry does) and writeConfig (stored as KConfig text). A layout is JSON:
//   {"desktops": [CONTAINMENT, ...], "panels": [CONTAINMENT, ...], "knownWidgetTypes": [...]}
//   CONTAINMENT = [WIDGET, ...] or {"id": 2, "type": "org.kde.panel", "screen": 0, "location": "top",
//                                   "opacity": "adaptive", "config": {...}, "widgets": [WIDGET, ...]}
//   WIDGET = {"id": 12, "type": "org.plasmafusion.dock", "config": {"General": {"magnify": "true"}}}
//
//   node fake-shell.js LAYOUT.json [WRITES.log] < SCRIPT   runs SCRIPT, saves the layout, prints
//                                                           the script's print() output
//   require("./fake-shell.js").run(script, layout, writes)  the same in-process
"use strict";

function convert(raw, def) {
    if (raw === undefined)
        return def;
    if (typeof def === "boolean")
        return /^(true|1|yes|on)$/i.test(raw);
    if (typeof def === "number") {
        const n = parseInt(raw, 10);
        return isNaN(n) ? def : n;
    }
    return raw;
}

// The highest id in the layout, for new widgets.
function maxId(layout) {
    let max = 0;
    for (const c of (layout.desktops || []).concat(layout.panels || [])) {
        if (!Array.isArray(c) && c.id)
            max = Math.max(max, c.id);
        for (const w of Array.isArray(c) ? c : c.widgets || [])
            max = Math.max(max, w.id);
    }
    return max;
}

function wrap(w, list, writes) {
    let group = [];
    return {
        get id() { return w.id; },
        get type() { return w.type; },
        get globalShortcut() { return w.shortcut || ""; },
        set globalShortcut(k) { w.shortcut = String(k); writes.push(`${w.id} globalShortcut=${k}`); },
        get index() { return list.indexOf(w); },
        set index(i) {
            list.splice(list.indexOf(w), 1);
            list.splice(i, 0, w);
            writes.push(`${w.id} index=${i}`);
        },
        get currentConfigGroup() { return group; },
        set currentConfigGroup(g) { group = g; },
        readConfig(key, def) {
            const g = w.config[group.join("][")] || {};
            return convert(g[key], def);
        },
        writeConfig(key, value) {
            const name = group.join("][");
            w.config[name] = w.config[name] || {};
            w.config[name][key] = String(value);
            writes.push(`${w.id} [${name}] ${key}=${String(value)}`);
        },
        remove() {
            list.splice(list.indexOf(w), 1);
            writes.push(`${w.id} removed`);
        },
    };
}

function run(script, layout, writes) {
    let out = "";
    function containment(c, at, kind) {
        // An array is a containment of widgets only; it becomes an object the first time a
        // property is written.
        const obj = () => {
            if (Array.isArray(layout[kind][at]))
                layout[kind][at] = { widgets: layout[kind][at] };
            return layout[kind][at];
        };
        const list = () => (Array.isArray(layout[kind][at]) ? layout[kind][at] : layout[kind][at].widgets);
        const prop = (name, def) => (Array.isArray(layout[kind][at]) ? def : layout[kind][at][name] ?? def);
        let group = [];
        return {
            get currentConfigGroup() { return group; },
            set currentConfigGroup(g) { group = g; },
            readConfig(key, def) {
                const g = prop("config", {})[group.join("][")] || {};
                return convert(g[key], def);
            },
            writeConfig(key, value) {
                const o = obj(), name = group.join("][");
                o.config = o.config || {};
                o.config[name] = o.config[name] || {};
                o.config[name][key] = String(value);
                writes.push(`containment ${prop("id", at)} [${name}] ${key}=${String(value)}`);
            },
            get id() { return prop("id", 0); },
            get type() { return prop("type", kind === "panels" ? "org.kde.panel" : "org.plasmafusion.desktop"); },
            get screen() { return prop("screen", 0); },
            get location() { return prop("location", kind === "panels" ? "top" : "floating"); },
            get opacity() { return prop("opacity", "adaptive"); },
            set opacity(v) { obj().opacity = String(v); writes.push(`containment ${prop("id", at)} opacity=${v}`); },
            widgets(type) {
                return list().filter((w) => type === undefined || w.type === type).map((w) => wrap(w, list(), writes));
            },
            addWidget(type) {
                const w = { id: maxId(layout) + 1, type: String(type), config: {} };
                list().push(w);
                writes.push(`${w.id} added ${w.type}`);
                return wrap(w, list(), writes);
            },
        };
    }
    const api = {
        desktops: () => (layout.desktops || []).map((c, i) => containment(c, i, "desktops")),
        panels: () => (layout.panels || []).map((c, i) => containment(c, i, "panels")),
        print: (s) => { out += String(s); },
    };
    const known = layout.knownWidgetTypes || [];
    // eslint-disable-next-line no-new-func
    new Function("desktops", "panels", "print", "knownWidgetTypes", script)(api.desktops, api.panels, api.print, known);
    return out;
}

module.exports = { run };

if (require.main === module) {
    const fs = require("fs");
    const layout = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    const writes = [];
    const script = fs.readFileSync(0, "utf8");
    const out = run(script, layout, writes);
    fs.writeFileSync(process.argv[2] + ".tmp", JSON.stringify(layout, null, 1));
    fs.renameSync(process.argv[2] + ".tmp", process.argv[2]);
    if (process.argv[3] && writes.length)
        fs.appendFileSync(process.argv[3], writes.join("\n") + "\n");
    process.stdout.write(out);
}
