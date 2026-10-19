// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
/*
    The settings page's "Export my settings…" runs this in plasmashell: the panels, for the
    settings file, printed as one line of JSON:
      {"version": 1, "screens": N, "panels": [PANEL, ...], "left": [REASON, ...]}
      REASON = "screen" (a panel of a screen that is not there) or "copy" (a dock copy)
      PANEL  = {"screen", "location", "height", "floating", "lengthMode", "alignment", "hiding",
                "opacity", "floatingApplets", "config": [GROUP, ...], "widgets": [WIDGET, ...]}
               and with lengthMode "custom" its "offset", "length", "minimumLength", "maximumLength"
      WIDGET = {"type", "shortcut", "config": [GROUP, ...]}
      GROUP  = {"group": ["General", ...], "keys": {"key": "text"}}
    A panel's and every widget's configuration is taken group by group (configGroups and
    configKeys, plasma-workspace 6.7.5 shell/scripting/applet.h), each value as the text KConfig
    keeps, which import-layout.js writes back as is. As Plasma's own layout dump does
    (ShellCorona::dumpCurrentLayoutJS, dumpconfigGroupJS) the [Applets] groups are left out (the
    widgets are listed on their own; a system tray makes its items again from its [General]
    lists), and so are the keys that name what the new panel gets anew: its screen, place,
    activity and plugin, and the ids of its widgets (AppletOrder, ItemsGeometries,
    SystrayContainmentId). Also left out: the keys that ask a widget for something once (the test
    hooks and requests), the power tier the power service sets (powerTier; it sets it again) and the
    panel's marks that name other panels (PlasmaFusion everyScreenCopy, standInFor). A key the
    service holds while the battery is low (plasmafusionrc [Power] UserWidgetValues,
    "WIDGET-ID/key=value,...", plasma-fusion-powerfx) is taken with the user's value.

    Panels left out: the ones "Dock on every screen" made ([PlasmaFusion] everyScreenCopy: that
    setting brings them back) and the ones of screens that are not there (their sizes cannot be
    read: plasmashell crashes on them); "left" says what was left out, for the settings page to
    tell. When no other dock is on a screen that is there (the main dock is on a monitor that is
    unplugged), the copy on the lowest screen is taken as the dock, as the settings page keeps it
    when "Dock on every screen" goes off: no longer a copy, listing every screen's windows.
*/
(function () {
    var DOCK = "org.plasmafusion.dock";
    var SKIP = ["debugAction", "debugPointerX", "debugHoverIndex", "splitRequest", "activateRequest", "openRequest",
                "pairRequest", "keepRequest", "pinRequest", "powerTier", "AppletOrder", "ItemsGeometries", "SystrayContainmentId"];
    // A containment's own keys at the top of its configuration (a widget's top is its
    // [Configuration] group, which has none of them).
    var ROOT_SKIP = ["activityId", "plugin", "location", "formfactor", "lastScreen"];
    var PANEL_MARKS = ["everyScreenCopy", "standInFor"];
    var held = {};
    String(ConfigFile("plasmafusionrc", "Power").readEntry("UserWidgetValues") || "").split(",").forEach(function (e) {
        var at = e.indexOf("=");
        if (at > 0) {
            held[e.slice(0, at)] = e.slice(at + 1);
        }
    });
    function truthy(value) {
        return value === true || String(value) === "true";
    }
    function mark(o, key) {
        o.currentConfigGroup = ["PlasmaFusion"];
        var value = String(o.readConfig(key, ""));
        o.currentConfigGroup = [];
        return value;
    }
    function isCopy(p) {
        if (truthy(mark(p, "everyScreenCopy"))) {
            return true;
        }
        var docks = p.widgets(DOCK);
        for (var d = 0; d < docks.length; ++d) {
            if (truthy(mark(docks[d], "everyScreenCopy"))) {
                return true;
            }
        }
        return false;
    }
    // O's configuration (a widget, or a panel with PANEL set).
    function configOf(o, panel) {
        var out = [];
        function walk(path) {
            o.currentConfigGroup = path;
            var keys = (o.configKeys || []).map(String);
            var groups = (o.configGroups || []).map(String);
            var values = {}, any = false;
            for (var k = 0; k < keys.length; ++k) {
                var key = keys[k];
                if (SKIP.indexOf(key) !== -1 || (path.length === 0 && ROOT_SKIP.indexOf(key) !== -1)
                    || (panel && path.join("/") === "PlasmaFusion" && PANEL_MARKS.indexOf(key) !== -1)) {
                    continue;
                }
                // The service holds keys of a widget's top groups ([General], [Appearance]).
                var user = !panel && path.length === 1 ? held[o.id + "/" + key] : undefined;
                values[key] = user !== undefined ? user : String(o.readConfig(key, ""));
                any = true;
            }
            if (any) {
                out.push({ group: path.slice(), keys: values });
            }
            for (var g = 0; g < groups.length; ++g) {
                if (groups[g] !== "Applets") {
                    walk(path.concat([groups[g]]));
                }
            }
        }
        walk([]);
        o.currentConfigGroup = [];
        return out;
    }
    // A copy the export takes as the dock: its mark goes, and it lists every screen's windows.
    function asDock(config) {
        return config.map(function (g) {
            var keys = {};
            for (var key in g.keys) {
                keys[key] = g.keys[key];
            }
            var name = g.group.join("/");
            if (name === "PlasmaFusion") {
                delete keys.everyScreenCopy;
            } else if (name === "General") {
                keys.showOnlyCurrentScreen = "false";
            }
            return { group: g.group, keys: keys };
        }).filter(function (g) { return Object.keys(g.keys).length > 0; });
    }
    var result = { version: 1, screens: screenCount, panels: [], left: [] };
    var ps = panels();
    var shown = function (p) { return p.screen >= 0 && p.screen < screenCount; };
    var dockTaken = null, original = false;
    for (var i = 0; i < ps.length; ++i) {
        if (!shown(ps[i]) || ps[i].widgets(DOCK).length === 0) {
            continue;
        }
        if (!isCopy(ps[i])) {
            original = true;
        } else if (dockTaken === null || ps[i].screen < dockTaken.screen) {
            dockTaken = ps[i];
        }
    }
    if (original) {
        dockTaken = null;
    }
    for (var i = 0; i < ps.length; ++i) {
        var p = ps[i];
        if (!shown(p)) {
            result.left.push("screen");
            continue;
        }
        var taken = dockTaken !== null && p.id === dockTaken.id;
        if (isCopy(p) && !taken) {
            result.left.push("copy");
            continue;
        }
        // The panel view's floatingApplets (the layout script explains it), kept per panel id.
        var floatingApplets = String(ConfigFile(ConfigFile("plasmashellrc", "PlasmaViews"), "Panel " + p.id).readEntry("floatingApplets"));
        var panel = { screen: p.screen, location: String(p.location), height: p.height, floating: !!p.floating,
                      lengthMode: String(p.lengthMode), alignment: String(p.alignment), hiding: String(p.hiding),
                      opacity: String(p.opacity), floatingApplets: floatingApplets === "1" || floatingApplets === "true",
                      config: configOf(p, true), widgets: [] };
        if (panel.lengthMode === "custom") {
            panel.offset = p.offset;
            panel.length = p.length;
            panel.minimumLength = p.minimumLength;
            panel.maximumLength = p.maximumLength;
        }
        // In the panel's order: widgets() lists them as they were made, Widget.index is their place
        // (the panel's AppletOrder; -1 when it does not list one, which then keeps its turn).
        var ws = [];
        var listed = p.widgets();
        for (var n = 0; n < listed.length; ++n) {
            ws.push({ w: listed[n], at: listed[n].index >= 0 ? listed[n].index : 1000 + n });
        }
        ws.sort(function (a, b) { return a.at - b.at; });
        ws = ws.map(function (e) { return e.w; });
        for (var j = 0; j < ws.length; ++j) {
            var config = configOf(ws[j], false);
            if (taken && String(ws[j].type) === DOCK) {
                config = asDock(config);
            }
            panel.widgets.push({ type: String(ws[j].type), shortcut: String(ws[j].globalShortcut || ""), config: config });
        }
        result.panels.push(panel);
    }
    print(JSON.stringify(result));
})();
