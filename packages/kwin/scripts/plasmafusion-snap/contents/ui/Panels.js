// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// The answer of the Global Theme's ensure-topbars.js, which the snap script runs in plasmashell at
// the session's start and when screens change: the lines it prints ("top bars: screens N, added A,
// completed C" and "docks: screens N, added M, ..."). New panels and widgets get the power tier's
// keys only when the power service applies its tier again, so the script asks for that when this
// says something was made. Pure logic (packages/kwin/tests/panels.test.js).

// Whether ensure-topbars.js made a top bar, completed one, or made a dock.
function addedWidgets(text) {
    var s = String(text || "");
    var bars = s.match(/added (\d+), completed (\d+)/);
    var docks = s.match(/docks: screens \d+, added (\d+)/);
    return (bars !== null && (Number(bars[1]) > 0 || Number(bars[2]) > 0)) || (docks !== null && Number(docks[1]) > 0);
}
