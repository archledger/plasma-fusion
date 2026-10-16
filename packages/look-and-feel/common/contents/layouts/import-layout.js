// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
/*
    The settings page's "Import settings…" runs this in plasmashell, with the panels of a settings
    file in front of it (var LAYOUT = {...}; what export-layout.js printed): they take the place of
    the panels there are. Each panel goes to its screen with its place, look and configuration, its
    widgets in order, and every widget's configuration written back as the text it was exported
    as. A panel of a screen this computer does not have goes to the first screen when the file puts
    no panel on that edge of it (a dock of a second monitor on a laptop alone), else it is left out
    ("Top bar on every screen" and "Dock on every screen" give the screens there are their bars and
    docks afterwards); a widget that is not installed is left out too. The widgets' shortcuts are
    the settings page's (it gives the keys the file names, as after a layout reset).

    With var PHASE = "remove" in front too, it only removes the panels there are and prints
    {"removed": N}; with PHASE = "add" it only adds the file's. The settings page runs the two
    apart, a moment from each other, as a layout reset unloads the old panels before it loads the
    new ones: a removed widget is deleted only on the shell's next turn (libplasma 6.7.5
    AppletPrivate::cleanUpAndDelete, deleteLater), its configuration already reset, and widgets of
    one kind share their state (quick settings' Instances), so new widgets started next to the old
    ones would count them. Without PHASE it does both. Adding prints one line of JSON:
      {"panels": N, "widgets": M, "screens": S, "notInstalled": [TYPE, ...], "leftOut": K}
    In each phase it prints {"error": "..."} when LAYOUT is not a layout of this version or has no
    panel, and changes nothing (the user is not left without panels).
*/
(function () {
    if (typeof LAYOUT !== "object" || LAYOUT === null || LAYOUT.version !== 1 || !Array.isArray(LAYOUT.panels)) {
        print(JSON.stringify({ error: "not a Plasma Fusion layout of version 1" }));
        return;
    }
    var phase = typeof PHASE === "string" ? PHASE : "";
    function made(widget) {
        return widget && typeof widget === "object" && widget.type !== undefined;
    }
    function configure(o, config) {
        config = Array.isArray(config) ? config : [];
        for (var c = 0; c < config.length; ++c) {
            o.currentConfigGroup = config[c].group;
            for (var key in config[c].keys) {
                o.writeConfig(key, String(config[c].keys[key]));
            }
        }
        o.currentConfigGroup = [];
    }
    var list = LAYOUT.panels.filter(function (d) { return d && typeof d === "object"; });
    if (list.length === 0 || screenCount < 1) {
        print(JSON.stringify({ error: "the file has no panel" }));
        return;
    }
    if (phase !== "add") {
        var old = panels();
        for (var i = 0; i < old.length; ++i) {
            old[i].remove();
        }
        if (phase === "remove") {
            print(JSON.stringify({ removed: old.length }));
            return;
        }
    }
    // Each panel's screen: its own, else the first one while the file has no panel on that edge
    // of it (-1: left out).
    var fits = function (d) { return d.screen >= 0 && d.screen < screenCount; };
    var edges = {};
    list.forEach(function (d) {
        if (fits(d)) {
            edges[d.screen + " " + d.location] = true;
        }
    });
    var screens = list.map(function (d) {
        if (fits(d)) {
            return d.screen;
        }
        if (edges["0 " + d.location]) {
            return -1;
        }
        edges["0 " + d.location] = true;
        return 0;
    });
    var result = { panels: 0, widgets: 0, screens: screenCount, notInstalled: [], leftOut: 0 };
    for (var p = 0; p < list.length; ++p) {
        var data = list[p];
        if (screens[p] < 0) {
            result.leftOut++;
            continue;
        }
        var panel = new Panel;
        panel.screen = screens[p];
        // The view reads it when the location is set (the layout script writes it first too).
        if (data.floatingApplets) {
            ConfigFile(ConfigFile("plasmashellrc", "PlasmaViews"), "Panel " + panel.id).writeEntry("floatingApplets", 1);
        }
        panel.location = data.location;
        panel.height = data.height;
        panel.floating = !!data.floating;
        panel.lengthMode = data.lengthMode;
        if (data.lengthMode === "custom") {
            panel.offset = data.offset;
            panel.length = data.length;
            panel.minimumLength = data.minimumLength;
            panel.maximumLength = data.maximumLength;
        }
        panel.alignment = data.alignment;
        panel.hiding = data.hiding;
        panel.opacity = data.opacity;
        configure(panel, data.config);
        result.panels++;
        var widgets = Array.isArray(data.widgets) ? data.widgets : [];
        for (var w = 0; w < widgets.length; ++w) {
            if (knownWidgetTypes.indexOf(widgets[w].type) === -1) {
                if (result.notInstalled.indexOf(widgets[w].type) === -1) {
                    result.notInstalled.push(widgets[w].type);
                }
                continue;
            }
            var widget = panel.addWidget(widgets[w].type);
            if (!made(widget)) {
                if (result.notInstalled.indexOf(widgets[w].type) === -1) {
                    result.notInstalled.push(widgets[w].type);
                }
                continue;
            }
            configure(widget, widgets[w].config);
            result.widgets++;
        }
    }
    print(JSON.stringify(result));
})();
