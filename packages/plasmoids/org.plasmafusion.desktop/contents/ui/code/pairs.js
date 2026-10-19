/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Saved app pairs on the home screen (board TabletPairs.dc.html, docs/parts/apppairs.md): a pair
    is an application entry of its own (org.plasmafusion.pair-ID.desktop, written by the
    plasma-fusion-app-pair helper), so the home screen holds it as a pinned app; its keys name the
    two apps and the split. Tested by tests/pairs.test.js (node).
*/

.pragma library

const PAIR = /^(?:applications:)?(org\.plasmafusion\.pair-[0-9A-Za-z]+\.desktop)$/;
const APP = /^[A-Za-z0-9._-]+\.desktop$/;

// The pair's desktop file id of a home screen favourite, or "" for anything else: the pinned apps
// model gives an app's storage id ("ID", plasma-workspace 6.7.5 AppEntry::id()), a pin request
// "applications:ID".
function pairId(favoriteId) {
    const m = PAIR.exec(String(favoriteId || ""));
    return m ? m[1] : "";
}

// A desktop file id as the pair's entry names an app: one file name, no path.
function validApp(id) {
    return APP.test(String(id || ""));
}

// The split as the tablet's divider snaps it: the left part, 1/3, 1/2 or 2/3.
function snapShare(value) {
    const s = Number(value);
    if (!isFinite(s)) {
        return 0.5;
    }
    return s < 0.4167 ? 0.3333 : s > 0.5833 ? 0.6667 : 0.5;
}

// The pair from its entry, through a reader of the desktop file's keys (QtCore Settings' value():
// "Desktop Entry/KEY"): {left, right, share}, or null when the entry is not a pair's.
function readPair(value) {
    const key = k => String(value("Desktop Entry/X-PlasmaFusion-Pair" + k) ?? "");
    const left = key("Left"), right = key("Right");
    if (!validApp(left) || !validApp(right) || left === right) {
        return null;
    }
    return { "left": left, "right": right, "share": snapShare(key("Share") || 0.5) };
}

// An app's name and icon from its desktop file (the same reader), the name in the language asked
// for ("de_DE": Name[de_DE], then Name[de], then Name): {name, icon}, or null without one.
function readApp(value, locale) {
    const entry = k => value("Desktop Entry/" + k);
    if (entry("Name") === undefined || entry("Name") === null) {
        return null;
    }
    const lang = String(locale || "");
    const keys = [];
    if (lang !== "") {
        keys.push("Name[" + lang + "]");
        const short = lang.split(/[_@.]/)[0];
        if (short !== lang) {
            keys.push("Name[" + short + "]");
        }
    }
    keys.push("Name");
    let name = "";
    for (const k of keys) {
        const v = entry(k);
        if (v !== undefined && v !== null && String(v) !== "") {
            name = Array.isArray(v) ? v.join(",") : String(v);
            break;
        }
    }
    const icon = entry("Icon");
    return { "name": name, "icon": icon === undefined || icon === null ? "" : String(icon) };
}

// The pair's name, both apps': "Dolphin · Firefox".
function label(leftName, rightName) {
    return String(leftName) + " · " + String(rightName);
}

// A desktop file id without its suffix: the name the Fusion icon theme draws an app's tile by.
function iconName(appId) {
    return String(appId || "").replace(/\.desktop$/, "");
}

// The dock's pairRequest "nonce:left:right:share" through desktop scripting: the dock of this
// screen only (as home.js splitScript), so a dock on every screen does not open it twice.
function pairScript(pair, screen, nonce) {
    const value = JSON.stringify(nonce + ":" + pair.left + ":" + pair.right + ":" + pair.share);
    return "(function () { var mine = null, any = null;"
        + " panels().forEach(function (p) { p.widgets(\"org.plasmafusion.dock\").forEach(function (w) {"
        + " if (any === null) { any = w; } if (mine === null && p.screen === " + Number(screen) + ") { mine = w; } }); });"
        + " var dock = mine !== null ? mine : any;"
        + " if (dock !== null) { dock.currentConfigGroup = [\"General\"]; dock.writeConfig(\"pairRequest\", " + value + "); } })();";
}

// The helper's command for "swap" or "remove" of a pair (by its id, which holds no character a
// shell reads): from the places the setup puts its helpers, in its order (tools/device/
// fusion-config.sh, HELPER_DIRS), as quick settings runs the copy-text helper.
function helperCommand(action, id) {
    if ((action !== "swap" && action !== "remove") || !PAIR.test("applications:" + id)) {
        return "";
    }
    return "sh -c 'for d in \"$HOME/.local/libexec/plasma-fusion\" /usr/local/libexec/plasma-fusion "
        + "/usr/libexec/plasma-fusion /usr/lib/plasma-fusion /run/current-system/sw/libexec/plasma-fusion; do "
        + "if [ -x \"$d/plasma-fusion-app-pair\" ]; then exec \"$d/plasma-fusion-app-pair\" " + action + " " + id + "; fi; done; "
        + "exit 127'";
}
