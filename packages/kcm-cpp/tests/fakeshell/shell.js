// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Test tooling (not installed): the part of Plasma's desktop scripting API the settings module
// uses, for fakeshell.cpp. Panels hold widgets in order; a widget's index is its place in that
// order and setting it moves the widget there (the panel's own rule: taken out, then put in at the
// index); geometry.x is 100 px per place. Layout file (JSON):
//   panels            [{ location, screen, opacity, height, config, widgets: [plugin id or { type,
//                     config }, ...], listDelayMs }]; a panel's and a widget's config map
//                     "Group/key" to a value; height defaults to 34 (top) and 72 (bottom)
//   knownWidgetTypes  plugin ids addWidget() can make (default: every id in the panels)
//   failAdd           plugin ids addWidget() fails for (it returns an Error, as plasmashell does)
//   insert            "x" (default: before the widget at the x given, as a drop there) or "end"
//   listDelayMs       a new widget is listed by widgets() only this long after addWidget() (a QML
//                     widget the shell loads for the first time is listed once it is built); a
//                     panel's own listDelayMs takes its place there (bars that build at different
//                     times)
//   screens           the number of screens (default: one more than the highest panel screen). A
//                     panel on a screen that is not there behaves as in Plasma 6.8: reading or
//                     writing its opacity or height crashes the shell (host.crash), as plasmashell
//                     crashes on the invalid config group of a missing screen
//   showOpacity       the state file also names each panel's opacity ("top 0 adaptive: ...")
//   showHeight        the state file also names each panel's height ("bottom 0 h72: ...")
//   showConfig        the state file also lists each widget's configuration after its id
//                     ("launcher{General/showPlaces=false}"), keys in order, and a panel's after
//                     its screen ("bottom 1{PlasmaFusion/everyScreenCopy=true}: ...")
//   scriptDelayMs     the shell answers a script only this long after it came (a shell that has
//   slowFrom          just started), from the slowFrom-th script on (default 1: every script)
//   failScripts       a script holding this text gets an error reply instead (a shell whose script
//                     fails or times out), as plasmashell answers a failing script

var state = { panels: [], nextId: 100, known: [], failAdd: [], insert: "x", listDelayMs: 0, showOpacity: false, showHeight: false, showConfig: false,
              scriptDelayMs: 0, slowFrom: 1, scripts: 0, failScripts: "" };
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
            id: state.nextId++,
            location: p.location || "top",
            screen: p.screen === undefined ? 0 : p.screen,
            opacity: p.opacity || "adaptive",
            height: p.height !== undefined ? p.height : ((p.location || "top") === "bottom" ? 72 : 34),
            config: p.config || {},
            listDelayMs: p.listDelayMs,
            items: (p.widgets || []).map(function (entry) {
                var type = typeof entry === "string" ? entry : entry.type;
                all.push(type);
                var w = makeWidget(type);
                if (typeof entry !== "string" && entry.config) {
                    for (var key in entry.config) {
                        w.config[key] = entry.config[key];
                    }
                }
                return w;
            })
        };
    });
    state.known = layout.knownWidgetTypes || all;
    state.failAdd = layout.failAdd || [];
    state.insert = layout.insert || "x";
    state.listDelayMs = layout.listDelayMs || 0;
    state.showOpacity = layout.showOpacity === true;
    state.showHeight = layout.showHeight === true;
    state.showConfig = layout.showConfig === true;
    state.scriptDelayMs = layout.scriptDelayMs || 0;
    state.slowFrom = layout.slowFrom || 1;
    state.failScripts = layout.failScripts || "";
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
    var o = {
        get id() { return panel.id; },
        // The containment's own configuration (not the panel's window settings of view()).
        currentConfigGroup: [],
        readConfig: function (key, fallback) {
            var v = panel.config[o.currentConfigGroup.join("/") + "/" + key];
            return v === undefined ? fallback : v;
        },
        writeConfig: function (key, value) {
            panel.config[o.currentConfigGroup.join("/") + "/" + key] = value;
        },
        remove: function () {
            var at = state.panels.indexOf(panel);
            if (at >= 0) {
                state.panels.splice(at, 1);
            }
        },
        get location() { return panel.location; },
        get screen() { return panel.screen; },
        get opacity() { view(panel, "opacity"); return panel.opacity; },
        set opacity(value) { view(panel, "opacity"); panel.opacity = value; },
        get height() { view(panel, "height"); return panel.height; },
        set height(value) { view(panel, "height"); panel.height = value; },
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
            w.listedAt = Date.now() + (panel.listDelayMs !== undefined ? panel.listDelayMs : state.listDelayMs);
            var at = panel.items.length;
            if (state.insert === "x" && typeof x === "number" && x >= 0) {
                at = Math.min(panel.items.length, Math.floor(x / 100) + 1);
            }
            panel.items.splice(at, 0, w);
            return widgetObject(panel, w);
        }
    };
    return o;
}

// Whether fakeshell answers SCRIPT with an error (failScripts).
function failsScript(script) {
    return state.failScripts !== "" && String(script).indexOf(state.failScripts) !== -1;
}

// How long fakeshell waits before it runs the next script (scriptDelayMs, slowFrom).
function nextScriptDelay() {
    state.scripts++;
    return state.scripts >= state.slowFrom ? state.scriptDelayMs : 0;
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
// opacity after the screen with showOpacity, and the height with showHeight).
function dumpLayout() {
    return state.panels.map(function (p) {
        // With showConfig a panel's own configuration follows its screen when it has any.
        var own = Object.keys(p.config).sort();
        var conf = state.showConfig && own.length > 0 ? "{" + own.map(function (k) { return k + "=" + p.config[k]; }).join(",") + "}" : "";
        return p.location + " " + p.screen + conf + (state.showOpacity ? " " + p.opacity : "") + (state.showHeight ? " h" + p.height : "") + ": " + p.items.map(function (w) {
            var name = w.type.replace(/^org\.(plasmafusion|kde\.plasma)\./, "");
            var keys = Object.keys(w.config).sort();
            if (!state.showConfig || keys.length === 0) {
                return name;
            }
            return name + "{" + keys.map(function (k) { return k + "=" + w.config[k]; }).join(",") + "}";
        }).join(" ");
    }).join("\n") + "\n";
}
