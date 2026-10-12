// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Test tooling (not installed): the part of Plasma's desktop scripting API the settings module
// uses, for fakeshell.cpp. Panels hold widgets in order; a widget's index is its place in that
// order and setting it moves the widget there (the panel's own rule: taken out, then put in at the
// index); geometry.x is 100 px per place. Layout file (JSON):
//   panels            [{ location, screen, opacity, widgets: [plugin id, ...] }]
//   knownWidgetTypes  plugin ids addWidget() can make (default: every id in the panels)
//   failAdd           plugin ids addWidget() fails for (it returns an Error, as plasmashell does)
//   insert            "x" (default: before the widget at the x given, as a drop there) or "end"
//   listDelayMs       a new widget is listed by widgets() only this long after addWidget() (a QML
//                     widget the shell loads for the first time is listed once it is built)
//   screens           the number of screens (default: one more than the highest panel screen). A
//                     panel on a screen that is not there behaves as in Plasma 6.8: reading or
//                     writing its opacity crashes the shell (host.crash), as plasmashell crashes on
//                     the invalid config group of a missing screen
//   showOpacity       the state file also names each panel's opacity ("top 0 adaptive: ...")

var state = { panels: [], nextId: 100, known: [], failAdd: [], insert: "x", listDelayMs: 0, showOpacity: false };
var knownWidgetTypes = [];
var screenCount = 1;

function makeWidget(type) {
    var w = { id: state.nextId++, type: type, listedAt: 0, config: {} };
    return w;
}

function loadLayout(text) {
    var layout = JSON.parse(text);
    var all = [];
    state.panels = (layout.panels || []).map(function (p) {
        return {
            location: p.location || "top",
            screen: p.screen === undefined ? 0 : p.screen,
            opacity: p.opacity || "adaptive",
            items: (p.widgets || []).map(function (type) {
                all.push(type);
                return makeWidget(type);
            })
        };
    });
    state.known = layout.knownWidgetTypes || all;
    state.failAdd = layout.failAdd || [];
    state.insert = layout.insert || "x";
    state.listDelayMs = layout.listDelayMs || 0;
    state.showOpacity = layout.showOpacity === true;
    knownWidgetTypes = state.known.slice();
    screenCount = layout.screens !== undefined ? layout.screens : state.panels.reduce(function (n, p) {
        return Math.max(n, p.screen + 1);
    }, 1);
}

function listed(w) {
    return Date.now() >= w.listedAt;
}

function widgetObject(panel, w) {
    var o = {
        get id() { return w.id; },
        get type() { return w.type; },
        get index() { return panel.items.indexOf(w); },
        set index(at) {
            var from = panel.items.indexOf(w);
            if (from < 0) {
                return;
            }
            panel.items.splice(from, 1);
            panel.items.splice(Math.max(0, Math.min(at, panel.items.length)), 0, w);
        },
        get geometry() { return { x: panel.items.indexOf(w) * 100, y: 0, width: 90, height: 32 }; },
        currentConfigGroup: [],
        readConfig: function (key, fallback) {
            var v = w.config[o.currentConfigGroup.join("/") + "/" + key];
            return v === undefined ? fallback : v;
        },
        writeConfig: function (key, value) {
            w.config[o.currentConfigGroup.join("/") + "/" + key] = value;
        },
        remove: function () {
            var at = panel.items.indexOf(w);
            if (at >= 0) {
                panel.items.splice(at, 1);
            }
        }
    };
    return o;
}

// The panel's window settings, which plasmashell reads from the config of the panel's screen.
function view(panel, what) {
    if (panel.screen >= screenCount) {
        host.crash("the " + what + " of a panel on missing screen " + panel.screen);
    }
}

function panelObject(panel) {
    return {
        get location() { return panel.location; },
        get screen() { return panel.screen; },
        get opacity() { view(panel, "opacity"); return panel.opacity; },
        set opacity(value) { view(panel, "opacity"); panel.opacity = value; },
        widgets: function (type) {
            return panel.items.filter(function (w) {
                return listed(w) && (!type || w.type === type);
            }).map(function (w) {
                return widgetObject(panel, w);
            });
        },
        addWidget: function (type, x) {
            if (state.known.indexOf(type) < 0 || state.failAdd.indexOf(type) >= 0) {
                return new Error("Could not create the " + type + " widget!");
            }
            var w = makeWidget(type);
            w.listedAt = Date.now() + state.listDelayMs;
            var at = panel.items.length;
            if (state.insert === "x" && typeof x === "number" && x >= 0) {
                at = Math.min(panel.items.length, Math.floor(x / 100) + 1);
            }
            panel.items.splice(at, 0, w);
            return widgetObject(panel, w);
        }
    };
}

function panels() {
    return state.panels.map(panelObject);
}

function desktops() {
    return [];
}

function print(text) {
    host.print(String(text));
}

// One line per panel: "top 0: appname quicksettings ..." with the plugin ids shortened (and the
// opacity after the screen with showOpacity).
function dumpLayout() {
    return state.panels.map(function (p) {
        return p.location + " " + p.screen + (state.showOpacity ? " " + p.opacity : "") + ": " + p.items.map(function (w) {
            return w.type.replace(/^org\.(plasmafusion|kde\.plasma)\./, "");
        }).join(" ");
    }).join("\n") + "\n";
}
