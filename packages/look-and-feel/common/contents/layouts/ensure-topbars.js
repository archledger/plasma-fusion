/*
    Plasma Fusion: a top bar on every screen (owner decision 8, ADAPTIVE 6). Run in plasmashell
    (org.kde.PlasmaShell.evaluateScript) by tools/device/fusion-config.sh --screens and by the KWin
    hot-plug handler when a screen is added. Idempotent: a screen that already has a top panel is
    left alone, and a bar is never removed (a screen that goes away takes its panels with it, and
    Plasma brings them back when it returns).

    A new bar holds the app name, the global menu of that screen's windows and the clock pill, like
    the bars the layout script puts on the other screens; the primary screen's bar with the tray and
    quick settings comes from the layout script. Prints one line: "top bars: screens N, added M".

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

function ensureTopBarsTextScale() {  // identical to the layout script's textScale()
    var pt = NaN;
    var font = ConfigFile("kdeglobals", "General").readEntry("font");
    if (font !== undefined && font !== null && String(font) !== "") {
        pt = parseFloat(String(font).split(",")[1]);
    }
    var s = pt > 0 ? pt / 9.75 : gridUnit / 18;
    return Math.max(0.85, Math.min(1.6, s));
}

(function () {
    var known = knownWidgetTypes;
    function add(container, candidates) {
        for (var i = 0; i < candidates.length; ++i) {
            if (known.indexOf(candidates[i]) !== -1) {
                var widget = container.addWidget(candidates[i]);
                if (widget && typeof widget === "object" && widget.type !== undefined) {
                    return widget;
                }
            }
        }
        return null;
    }
    var hasTop = {};
    var ps = panels();
    // Only once plasmashell has loaded its layout: KWin runs this after its own start too, and a
    // plasmashell that answered before loading its panels got a second top bar (ThinkPad,
    // 2026-09-30). A top panel without a screen (not placed yet, or kept from a screen that went
    // away) may still be placed by Plasma, so no bar is added while one exists.
    if (ps.length === 0 || desktops().length === 0) {
        print("top bars: skipped, the layout is not loaded yet");
        return;
    }
    var unplaced = 0;
    for (var i = 0; i < ps.length; ++i) {
        if (ps[i].location !== "top") {
            continue;
        }
        if (ps[i].screen < 0 || ps[i].screen >= screenCount) {
            unplaced++;
        } else {
            hasTop[ps[i].screen] = true;
        }
    }
    if (unplaced > 0) {
        print("top bars: skipped, " + unplaced + " top panel(s) without a screen");
        return;
    }
    var added = 0;
    for (var sc = 0; sc < screenCount; ++sc) {
        if (hasTop[sc]) {
            continue;
        }
        var bar = new Panel;
        bar.screen = sc;
        ConfigFile(ConfigFile("plasmashellrc", "PlasmaViews"), "Panel " + bar.id).writeEntry("floatingApplets", 1);
        bar.location = "top";
        bar.height = Math.round(34 * ensureTopBarsTextScale());
        bar.floating = false;
        bar.lengthMode = "fill";
        bar.alignment = "center";
        bar.hiding = "none";
        bar.opacity = "adaptive";
        add(bar, ["org.plasmafusion.appname", "org.kde.plasma.kickoff"]);
        var menu = add(bar, ["org.kde.plasma.appmenu"]);
        if (menu) {
            menu.currentConfigGroup = ["Appearance"];
            menu.writeConfig("allScreens", false);
            menu.currentConfigGroup = [];
        }
        add(bar, ["org.kde.plasma.panelspacer"]);
        if (!add(bar, ["org.plasmafusion.clockpill"])) {
            add(bar, ["org.kde.plasma.digitalclock"]);
        }
        add(bar, ["org.kde.plasma.panelspacer"]);
        added++;
    }
    print("top bars: screens " + screenCount + ", added " + added);
})();
