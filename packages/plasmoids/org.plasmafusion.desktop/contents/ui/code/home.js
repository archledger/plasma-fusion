/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The tablet home screen's free side (board TabletSplit.dc.html): one app fills the left or the
    right part of the work area, top to bottom, and nothing else is shown beside it. The home screen
    then offers the apps there ("Pick an app for this side") instead of a home page cut off under the
    app. Tested by tests/freeside.test.js (node).
*/

.pragma library

// KWin's quick tiles, with the snap script's gaps, sit a few pixels inside the work area.
const EDGE = 24;
// A free part narrower than this holds no column of apps.
const MIN_FREE = 240;

// More than the gaps' worth of overlap on both axes.
function overlaps(a, b) {
    return a.x < b.x + b.width - EDGE && b.x < a.x + a.width - EDGE
        && a.y < b.y + b.height - EDGE && b.y < a.y + a.height - EDGE;
}

// windows: the shown windows of this screen, desktop and activity ([{x, y, width, height, appId}],
// in the work area's coordinates); area: the work area {x, y, width, height}. Returns the free part
// {side: "left" | "right", x, y, width, height, appId} (appId: the app beside it), or null.
function freeSide(windows, area) {
    const shown = (windows || []).filter(w => w && w.width > 0 && w.height > 0);
    const right = area.x + area.width;
    const bottom = area.y + area.height;
    for (const w of shown) {
        // Top to bottom, at one edge only (a maximized window is at both), and not all but a sliver.
        const fills = w.y <= area.y + EDGE && w.y + w.height >= bottom - EDGE;
        const atLeft = w.x <= area.x + EDGE;
        const atRight = w.x + w.width >= right - EDGE;
        if (!fills || atLeft === atRight) {
            continue;
        }
        const free = atLeft
            ? { side: "right", x: w.x + w.width, y: area.y, width: right - (w.x + w.width), height: area.height }
            : { side: "left", x: area.x, y: area.y, width: w.x - area.x, height: area.height };
        if (free.width < MIN_FREE || shown.some(other => other !== w && overlaps(other, free))) {
            continue;
        }
        free.appId = String(w.appId || "");
        return free;
    }
    return null;
}

// Two app ids of the same app: desktop file names ("org.kde.dolphin.desktop", or a favorite's
// "applications:..." id) from the home screen, the task model's AppId with the suffix up to Plasma
// 6.7 and without it from 6.8 on.
function sameApp(a, b) {
    const bare = id => String(id || "").replace(/^applications:/, "").replace(/\.desktop$/, "");
    return bare(a) !== "" && bare(a) === bare(b);
}

// Whether two answers are the same (no relayout for an unchanged one).
function sameFree(a, b) {
    if (!a || !b) {
        return a === b;
    }
    return a.side === b.side && a.appId === b.appId && Math.round(a.x) === Math.round(b.x)
        && Math.round(a.y) === Math.round(b.y) && Math.round(a.width) === Math.round(b.width)
        && Math.round(a.height) === Math.round(b.height);
}

// The desktop scripting snippet that hands a split request ("<side>:<nonce>:<app>.desktop") to
// one dock: the dock of the home screen's screen (with a dock on every screen, each would start the
// app and move the windows), else the first dock there is (a dock on the main screen only).
function splitScript(side, appId, screen, nonce) {
    const value = JSON.stringify(side + ":" + nonce + ":" + appId);
    return "(function () { var mine = null, any = null;"
        + " panels().forEach(function (p) { p.widgets(\"org.plasmafusion.dock\").forEach(function (w) {"
        + " if (any === null) { any = w; } if (mine === null && p.screen === " + Number(screen) + ") { mine = w; } }); });"
        + " var dock = mine !== null ? mine : any;"
        + " if (dock !== null) { dock.currentConfigGroup = [\"General\"]; dock.writeConfig(\"splitRequest\", " + value + "); } })();";
}
