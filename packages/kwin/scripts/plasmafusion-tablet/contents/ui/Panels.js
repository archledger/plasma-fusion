// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// The panel script (TABLET 3.6), run in plasmashell. Idempotent; never touches panels the user
// added. The tablet top bar height uses the layout script's text scale. The laptop height is
// saved once per panel and never as the tablet height (a plasmashell that restarted in tablet
// posture must not make the tablet size the laptop size). TABLET 3.6 also switched the stock
// appmenu's compactView here; that write crashed plasmashell 6.7.5 (the applet changes its
// representation inside the scripting writeConfig while its layout is updated), so the
// compact menu is left to the top-bar widgets.
//
// Pixel grid (research H-hidpi 3.6, owner OK 2026-10-01): the tablet top bar and dock get the
// smallest height at or above their size that is a whole number of device pixels at the screen's
// scale, so their edges are crisp: at 4/3 the top bar 44 -> 45 (60 px), the dock 80 -> 81 (108 px)
// and the dock's bottom strip 20 -> 21 (28 px; its config tabletStripHeight, as plasmashell's QML
// only sees Wayland's rounded integer scale); at 1.25, 1.5 or 2 the sizes stay. The laptop sizes
// are the boards' and stay as they are. A dock's laptop height is the plate of its size (the
// dock's dockSize: Small 60, Medium 72, Large 78 px, board DockSize.dc.html), which the settings
// page sets with the size. A dock on the left or right (board DockPosition.dc.html) is at the
// bottom in tablet posture, as on the Tablet board, and goes back to its side after (its
// laptopLocation, saved with the height).
//
// Panels on a screen that is gone are skipped. Their height, hiding and the other sizes of a
// scripting Panel come from the panel's window, or without one from its config for its screen;
// for a screen that is not there that config is an invalid KConfigGroup, and reading it crashes
// plasmashell (SIGSEGV in KConfigGroup::readEntry from WorkspaceScripting::Panel). Plasma 6.8
// keeps a panel on its last screen, so a top bar of a monitor that was unplugged crashed every
// shell start: the script runs when the panels appear. Plasma 6.7 reports such a panel on screen
// -1. The panel gets its posture when its screen comes back (its window appears then). While the
// shell has not loaded its layout or has no screen yet (early in its start, or while KWin has no
// output), or no Fusion panel is on a screen yet (Plasma 6.7 has every panel on -1 until it has
// made their windows), the script prints "not ready" and is asked again.
function panelScript(isTablet, hiding, scale) {
    return "var TABLET = " + (isTablet ? "true" : "false") + ", DOCK_HIDING = \"" + hiding + "\", SCALE = " + scale + ";\n"
        + "function snap(h) {\n"
        + "    if (!(SCALE > 0)) return h;\n"
        + "    for (var x = h; x < h + 6; ++x) { var d = x * SCALE; if (Math.abs(d - Math.round(d)) < 0.01) return x; }\n"
        + "    return h;\n"
        + "}\n"
        + "var HEIGHT_DOCK = snap(80), STRIP = snap(20);\n"
        + "function textScale() {\n"
        + "    var pt = NaN, font = ConfigFile(\"kdeglobals\", \"General\").readEntry(\"font\");\n"
        + "    if (font !== undefined && font !== null && String(font) !== \"\") pt = parseFloat(String(font).split(\",\")[1]);\n"
        + "    var s = pt > 0 ? pt / 9.75 : gridUnit / 18;\n"
        + "    return Math.max(0.85, Math.min(1.6, s));\n"
        + "}\n"
        + "var HEIGHT_TOP = snap(Math.round(44 * textScale())), done = [], skipped = 0;\n"
        + "function dockPlate(p) {\n"
        + "    var size = 1;\n"
        + "    p.widgets(\"org.plasmafusion.dock\").forEach(function (w) { w.currentConfigGroup = [\"General\"]; size = Number(w.readConfig(\"dockSize\", 1)); });\n"
        + "    return [60, 72, 78][size] || 72;\n"
        + "}\n"
        + "var all = panels(), ready = all.length > 0 && desktops().length > 0 && screenCount > 0;\n"
        + "if (ready) all.forEach(function (p) {\n"
        + "    var ws = p.widgets(), types = [];\n"
        + "    for (var i = 0; i < ws.length; ++i) types.push(ws[i].type);\n"
        + "    var isTop = types.indexOf(\"org.plasmafusion.quicksettings\") >= 0 || types.indexOf(\"org.plasmafusion.clockpill\") >= 0;\n"
        + "    var isDock = types.indexOf(\"org.plasmafusion.dock\") >= 0;\n"
        + "    if (!isTop && !isDock) return;\n"
        + "    if (!(p.screen >= 0 && p.screen < screenCount)) { ++skipped; return; }\n"
        + "    p.currentConfigGroup = [\"PlasmaFusion\"];\n"
        + "    var applied = p.readConfig(\"tabletApplied\", false) === true || p.readConfig(\"tabletApplied\", \"\") === \"true\";\n"
        + "    var h = isTop ? HEIGHT_TOP : HEIGHT_DOCK, laptop = isTop ? Math.round(34 * textScale()) : dockPlate(p);\n"
        + "    if (TABLET) {\n"
        + "        if (!applied) {\n"
        + "            p.writeConfig(\"laptopHeight\", p.height == h || (isDock && (p.height == 88 || p.height == 96)) ? laptop : p.height);\n"
        + "            p.writeConfig(\"laptopHiding\", p.hiding);\n"
        + "            if (isDock) p.writeConfig(\"laptopLocation\", String(p.location));\n"
        + "            p.writeConfig(\"tabletApplied\", true);\n"
        + "        }\n"
        + "        if (isDock && p.location != \"bottom\") p.location = \"bottom\";\n"
        + "        if (p.height != h) p.height = h;\n"
        + "        if (isDock && p.hiding != DOCK_HIDING) p.hiding = DOCK_HIDING;\n"
        + "        if (isDock) p.widgets(\"org.plasmafusion.dock\").forEach(function (w) {\n"
        + "            w.currentConfigGroup = [\"General\"];\n"
        + "            if (Number(w.readConfig(\"tabletStripHeight\", 20)) != STRIP) w.writeConfig(\"tabletStripHeight\", STRIP);\n"
        + "        });\n"
        + "    } else if (applied) {\n"
        + "        var saved = Number(p.readConfig(\"laptopHeight\", laptop));\n"
        + "        if (isDock && (saved == 88 || saved == 96)) saved = laptop;\n"
        + "        if (isDock) {\n"
        + "            var side = String(p.readConfig(\"laptopLocation\", \"bottom\"));\n"
        + "            if ((side == \"left\" || side == \"right\") && p.location != side) p.location = side;\n"
        + "        }\n"
        + "        p.height = saved > 0 && saved != h ? saved : laptop;\n"
        + "        if (isDock) p.hiding = String(p.readConfig(\"laptopHiding\", \"dodgewindows\"));\n"
        + "        p.writeConfig(\"tabletApplied\", false);\n"
        + "    }\n"
        + "    p.currentConfigGroup = [];\n"
        + "    done.push((isTop ? \"top \" : \"dock \") + p.height + (isDock ? \" \" + p.hiding + (p.location != \"bottom\" ? \" \" + p.location : \"\") : \"\"));\n"
        + "});\n"
        + "if (done.length === 0 && skipped > 0) ready = false;\n"
        + "if (skipped > 0) done.push(skipped + \" without a screen skipped\");\n"
        + "print(ready ? done.join(\", \") : \"not ready\");\n";
}

// When to ask again after plasmashell did not run the script (not on the bus yet at the session's
// start, restarting after a crash) or answered "not ready": after 1, 2, 4, 8, 16 and 32 s, about
// a minute in all, as long as the parity VM's slowest start; -1 when it is time to give up (the
// panels' windows appearing later run the script again anyway).
var retryLimit = 6;
function retryDelay(attempt) {
    return attempt >= 0 && attempt < retryLimit ? 1000 * Math.pow(2, attempt) : -1;
}

// Whether plasmashell's answer means it has not loaded its layout yet.
function notReady(answer) {
    return String(answer).trim() === "not ready";
}
