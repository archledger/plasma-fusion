// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// Touchpad gestures you can set (board Gestures.dc.html): the gestures KWin 6.7.5 leaves free,
// each with the kwinrc [Script-plasmafusion-snap] key the settings page writes and its default.
// KWin takes every touchpad gesture with three or more fingers and has no setting for its own
// (four fingers up, down, left and right; a three-finger pinch; three fingers sideways with more
// than one column of desktops, up and down with more than one row), so a gesture both take does
// both: the settings page says so on the row. Pure logic, plain values in and out
// (packages/kwin/tests/gestures.test.js); main.qml listens to the gestures and runs the actions.

// Each gesture: its key, KWin's handler type and its direction and finger count, and the default.
var GESTURES = [
    { key: "GestureSwipeUp3", kind: "swipe", direction: "up", fingers: 3, fallback: "overview" },
    { key: "GestureSwipeDown3", kind: "swipe", direction: "down", fingers: 3, fallback: "desktop" },
    { key: "GestureSwipeLeft3", kind: "swipe", direction: "left", fingers: 3, fallback: "none" },
    { key: "GestureSwipeRight3", kind: "swipe", direction: "right", fingers: 3, fallback: "none" },
    { key: "GesturePinchIn4", kind: "pinch", direction: "in", fingers: 4, fallback: "launcher" },
    { key: "GesturePinchOut4", kind: "pinch", direction: "out", fingers: 4, fallback: "desktop" },
];

// What a gesture can do, as the settings page writes it (its GestureAction values, in order).
var ACTIONS = ["none", "overview", "desktop", "grid", "windows", "launcher", "quicksettings", "notifications", "snaplayouts"];

// The gesture of KEY, or null.
function gesture(key) {
    for (let i = 0; i < GESTURES.length; ++i) {
        if (GESTURES[i].key === key) {
            return GESTURES[i];
        }
    }
    return null;
}

// The action the setting VALUE names; one that is empty or unknown (a later version's, a typo)
// is the gesture's default.
function actionFor(key, value) {
    const g = gesture(key);
    const name = value === undefined || value === null ? "" : String(value).trim().toLowerCase();
    if (ACTIONS.indexOf(name) >= 0) {
        return name;
    }
    return g ? g.fallback : "none";
}

// The KWin global shortcut (component kwin) an action invokes, or "" for the ones the script runs
// another way (Show desktop, the launcher, quick settings, notifications, the snap picker).
function kwinShortcut(action) {
    switch (action) {
    case "overview":
        return "Overview";
    case "grid":
        return "Grid View";
    case "windows":
        return "Expose";
    default:
        return "";
    }
}

// KWin's desktop switch animations, which hold KWin's full-screen effect while they run (KWin
// 6.7.5 plugins/slide/slide.cpp, plugins/fadedesktop): Overview, its grid and All windows do not
// start meanwhile (effect/quickeffect.cpp QuickSceneEffect::startInternal).
var DESKTOP_SWITCH_EFFECTS = ["slide", "fadedesktop"];

// Whether KWin switches desktops now, from its active effects (org.kde.kwin.Effects
// activeEffects: a list, or its text with the names separated by commas): an action that opens one
// of KWin's effects waits until the switch ends, as KWin also switches desktops with three fingers
// sideways when there is more than one column of them (up and down with more than one row).
function desktopSwitching(activeEffects) {
    const names = Array.isArray(activeEffects) ? activeEffects : String(activeEffects || "").split(",");
    return names.some(name => DESKTOP_SWITCH_EFFECTS.indexOf(String(name).trim()) >= 0);
}

// Quick settings' openRequest mode for an action (its contents/code/requests.js), or "".
function quickSettingsMode(action) {
    switch (action) {
    case "quicksettings":
        return "toggle";
    case "notifications":
        return "notifications";
    default:
        return "";
    }
}

// The desktop script that hands quick settings an openRequest "<mode>:<nonce>": the widget on
// KWin's active screen acts on it (no output named).
function quickSettingsScript(mode, nonce) {
    const request = JSON.stringify(mode + ":" + nonce);
    return "panels().forEach(function (p) { p.widgets(\"org.plasmafusion.quicksettings\").forEach(function (w) {"
        + " w.currentConfigGroup = [\"General\"]; w.writeConfig(\"openRequest\", " + request + "); }); });";
}
