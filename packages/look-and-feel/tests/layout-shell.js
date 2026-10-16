// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// A stand-in for plasmashell's layout scripting (plasma-workspace 6.7.5 shell/scripting), enough
// for the Global Theme's desktop layout script, ensure-topbars.js and the Add Panel templates: `new
// Panel` and the panel
// properties the scripts set (screen, location, height, floating, lengthMode, alignment, hiding,
// opacity), panels(), panelIds and panelById() (the Add Panel templates), desktops(), desktopsForActivity(), currentActivity(), screenCount,
// screenGeometry(), knownWidgetTypes, gridUnit, fileExists(), ConfigFile() (nested too) with
// readEntry and writeEntry, a containment's id, type, screen, wallpaperPlugin, widgets([TYPE]),
// addWidget() (an Error for a type in failAdd) and remove(), a widget's id, type and
// userBackgroundHints, and for both currentConfigGroup, readConfig and writeConfig. Test tooling
// only.
//
//   const { shell } = require("./layout-shell.js");
//   const s = shell({ screens: [[1920, 1080], [1280, 1024]], files: { plasmafusionrc: { TopBar: {...} } },
//                     panels: [...existing panels, as returned by s.panels...] });
//   s.run(scriptText); s.panels, s.desktops, s.files, s.output
"use strict";

const KNOWN = [
    "org.plasmafusion.appname", "org.plasmafusion.clockpill", "org.plasmafusion.quicksettings",
    "org.plasmafusion.pen", "org.plasmafusion.launcher", "org.plasmafusion.dock", "org.plasmafusion.meters",
    "org.plasmafusion.weathercard", "org.plasmafusion.calendarcard", "org.plasmafusion.systemcard",
    "org.plasmafusion.desktop", "org.plasmafusion.livechips", "org.kde.plasma.systemtray", "org.kde.plasma.appmenu",
    "org.kde.plasma.panelspacer", "org.kde.plasma.kickoff", "org.kde.plasma.digitalclock",
];

function shell(options) {
    const opts = options || {};
    const screens = opts.screens || [[1920, 1080]];
    const files = opts.files || {};
    // The widgets plasmashell knows (opts.without: ones not installed; opts.failAdd: ones it cannot
    // make, addWidget giving an Error as plasma-workspace 6.7.5's Containment::addWidget does).
    const known = KNOWN.filter((t) => (opts.without || []).indexOf(t) === -1);
    const failAdd = opts.failAdd || [];
    const panels = opts.panels || [];
    const desktops = opts.desktops || screens.map((s, i) => ({ id: 100 + i, type: "org.plasmafusion.desktop", screen: i, config: {}, widgets: [] }));
    let nextId = 1 + Math.max(0, ...panels.map((p) => p.id), ...panels.flatMap((p) => p.widgets.map((w) => w.id)),
                              ...desktops.map((d) => d.id), ...desktops.flatMap((d) => d.widgets.map((w) => w.id)));
    let output = "";

    function configurable(o) {
        let group = [];
        return {
            get currentConfigGroup() { return group; },
            set currentConfigGroup(g) { group = g; },
            // The keys set in the current group (Plasma's Widget.configKeys).
            get configKeys() { return Object.keys((o.config || {})[group.join("][")] || {}); },
            readConfig(key, def) {
                const g = (o.config || {})[group.join("][")] || {};
                if (g[key] === undefined)
                    return def;
                // KConfig converts to the default's type: a list read with a text default comes
                // back as its comma-joined text (KConfigGroup::readEntry with a QString default).
                return typeof def === "string" && Array.isArray(g[key]) ? g[key].join(",") : g[key];
            },
            writeConfig(key, value) {
                const name = group.join("][");
                o.config = o.config || {};
                o.config[name] = o.config[name] || {};
                o.config[name][key] = Array.isArray(value) ? value.slice() : value;
            },
        };
    }
    // A widget's place in its panel: 100 px a widget, in order (enough to place one before another).
    function widget(w, c) {
        return Object.assign(configurable(w), {
            get id() { return w.id; },
            get type() { return w.type; },
            get geometry() { return c ? { x: c.widgets.indexOf(w) * 100, y: 0, width: 90, height: 34 } : undefined; },
            set userBackgroundHints(v) { w.userBackgroundHints = v; },
            get userBackgroundHints() { return w.userBackgroundHints; },
        });
    }
    function containment(c) {
        const api = configurable(c);
        api.widgets = (type) => c.widgets.filter((w) => type === undefined || w.type === type).map((w) => widget(w, c));
        // addWidget(type) appends; addWidget(type, x, y, w, h) puts it at x, before the widget there,
        // as a panel does.
        api.addWidget = (type, x) => {
            if (known.indexOf(type) === -1)
                return null;
            if (failAdd.indexOf(type) !== -1)
                return new Error("Could not create the " + type + " widget!");
            const w = { id: nextId++, type: type, config: {} };
            const at = typeof x === "number" ? c.widgets.findIndex((o, i) => i * 100 > x) : -1;
            if (at === -1)
                c.widgets.push(w);
            else
                c.widgets.splice(at, 0, w);
            return widget(w, c);
        };
        for (const key of ["screen", "location", "height", "floating", "lengthMode", "alignment", "hiding", "opacity",
                           "wallpaperPlugin"]) {
            Object.defineProperty(api, key, { get: () => c[key], set: (v) => { c[key] = v; }, enumerable: true });
        }
        // Containment.remove(): the panel goes, with its widgets.
        api.remove = () => {
            const at = panels.indexOf(c);
            if (at !== -1)
                panels.splice(at, 1);
        };
        Object.defineProperty(api, "id", { get: () => c.id });
        Object.defineProperty(api, "type", { get: () => c.type });
        return api;
    }
    function Panel() {
        const p = { id: nextId++, type: "org.kde.panel", screen: -1, location: "floating", opacity: "adaptive", config: {}, widgets: [] };
        panels.push(p);
        return containment(p);
    }
    function configFile(parent, group) {
        // ConfigFile("file", "group") or ConfigFile(ConfigFile(...), "subgroup")
        const path = typeof parent === "string" ? { file: parent, groups: [group] } : { file: parent.path.file, groups: parent.path.groups.concat([group]) };
        const name = path.groups.join("][");
        return {
            path: path,
            readEntry(key) {
                const g = (files[path.file] || {})[name] || {};
                return g[key];
            },
            writeEntry(key, value) {
                files[path.file] = files[path.file] || {};
                files[path.file][name] = files[path.file][name] || {};
                files[path.file][name][key] = String(value);
            },
        };
    }
    function run(script) {
        const api = {
            Panel: Panel,
            panels: () => panels.map(containment),
            panelIds: panels.map((p) => p.id),
            panelById: (id) => { const p = panels.find((c) => c.id === id); return p ? containment(p) : null; },
            desktops: () => desktops.map(containment),
            desktopsForActivity: () => desktops.map(containment),
            currentActivity: () => "activity",
            screenCount: screens.length,
            screenGeometry: (i) => ({ x: 0, y: 0, width: screens[i][0], height: screens[i][1] }),
            knownWidgetTypes: known,
            gridUnit: 18,
            fileExists: () => false,
            ConfigFile: configFile,
            print: (s) => { output += String(s) + "\n"; },
        };
        const names = Object.keys(api);
        // eslint-disable-next-line no-new-func
        new Function(...names, script)(...names.map((n) => api[n]));
        return output;
    }
    return { run, panels, desktops, files, get output() { return output; } };
}

module.exports = { shell };
