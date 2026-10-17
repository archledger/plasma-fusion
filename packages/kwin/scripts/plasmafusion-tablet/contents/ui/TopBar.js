// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// The top bar's hidden state for the island (board Island.dc.html). A top bar that hides (the
// settings page's "Hide the top bar automatically") is hidden by KWin itself: plasmashell asks for
// an auto-hide screen edge and KWin hides the panel's window until the pointer touches the edge
// (KWin 6.7.5 LayerShellV1Window::reserveScreenEdge, Window::setHidden). Plasmashell tells its
// widgets nothing about it, but KWin's scripts see the window's `hidden`. This script passes it on
// to the live chips of each screen's bar ([General] barHidden), which show the island while it is
// set.

// Whether W (a KWin window) is a top bar of plasmashell on OUTPUT {x, y, width, height}: a panel
// window along the whole top of the output (the bar fills its width; the dock and the island are
// shorter and narrower).
function isTopBar(w, output) {
    if (!w || !w.dock || String(w.resourceClass) !== "plasmashell" || !output) {
        return false;
    }
    return Math.abs(w.y - output.y) <= 1 && Math.abs(w.x - output.x) <= 1 && w.width >= output.width - 2
        && w.height > 0 && w.height <= output.height / 4;
}

// The top bars among WINDOWS (plasmashell's panel windows), as barState() takes them, by their
// geometry now (a panel moved to another edge or made narrower is no bar any more); OUTPUT_OF(w)
// gives a window's output {x, y, width, height}.
function barsOf(windows, outputOf) {
    var bars = [];
    for (var i = 0; i < windows.length; ++i) {
        var output = outputOf(windows[i]);
        if (isTopBar(windows[i], output)) {
            bars.push({ x: output.x, y: output.y, hidden: windows[i].hidden === true });
        }
    }
    return bars;
}

// The bars as plasmashell gets them, from BARS [{x, y, hidden}] (their outputs' corners): one per
// screen, hidden while any panel window along its top is (KWin sees no widgets: another full-width
// top panel there is a bar too, and only a panel that hides can be hidden; barScript() then asks
// the live chips' own panel whether it hides), in a fixed order, so that the same state sends the
// same text (and nothing is sent again).
function barState(bars) {
    var byCorner = {};
    bars.forEach(function (b) {
        var key = Math.round(b.x) + "," + Math.round(b.y);
        var was = byCorner[key];
        byCorner[key] = { x: Math.round(b.x), y: Math.round(b.y), hidden: b.hidden === true || (was !== undefined && was.hidden) };
    });
    return Object.keys(byCorner).map(function (k) { return byCorner[k]; })
        .sort(function (a, b) { return a.x - b.x || a.y - b.y; });
}

// The script for plasmashell: every live chips widget in a panel on a screen gets barHidden true
// while the bar of its screen (the screen's corner, screenGeometry()) is hidden and its own panel
// is one that hides (another top panel there may be the one hidden), else false;
// written only when it changes. Panels on a screen that is gone are skipped (reading their
// config crashes plasmashell, Panels.js). Prints "island: N widgets, M changed".
function barScript(bars) {
    return "var BARS = " + JSON.stringify(barState(bars)) + ", n = 0, changed = 0;\n"
        + "panels().forEach(function (p) {\n"
        + "    var chips = p.widgets(\"org.plasmafusion.livechips\");\n"
        + "    if (chips.length === 0 || !(p.screen >= 0 && p.screen < screenCount)) return;\n"
        + "    var g = screenGeometry(p.screen), hidden = false, hides = String(p.hiding) === \"autohide\";\n"
        + "    for (var i = 0; i < BARS.length; ++i) {\n"
        + "        if (Math.abs(BARS[i].x - g.x) < 1 && Math.abs(BARS[i].y - g.y) < 1) hidden = hides && BARS[i].hidden;\n"
        + "    }\n"
        + "    chips.forEach(function (w) {\n"
        + "        w.currentConfigGroup = [\"General\"];\n"
        + "        var was = w.readConfig(\"barHidden\", false) === true || w.readConfig(\"barHidden\", \"\") === \"true\";\n"
        + "        if (was !== hidden) { w.writeConfig(\"barHidden\", hidden); ++changed; }\n"
        + "        ++n;\n"
        + "    });\n"
        + "});\n"
        + "print(\"island: \" + n + \" widgets, \" + changed + \" changed\");\n";
}
