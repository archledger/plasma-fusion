/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Full screen off in tablet posture (board TabletSnap.dc.html): a window always has a place, so
    one taken out of full screen takes a half instead of floating where a finger cannot move it.
    Tested by packages/kwin/tests/tablet-snap.test.js (node).
*/

.pragma library

// Which half a quick tile is, from its geometry relative to the work area (the split divider's
// test, SplitDivider.qml).
function isLeft(g) {
    return !!g && g.x < 0.01 && g.width < 0.99 && g.height > 0.99;
}
function isRight(g) {
    return !!g && g.x > 0.01 && g.x + g.width > 0.99 && g.height > 0.99;
}

// tiles: the relative geometries of the quick tiles the other shown windows of the screen and
// desktop sit in; minWidth: the window's minimum width; half: a half's width. The free half, the
// right one when both are free or both taken; "" when the window does not fit a half (it floats,
// as before).
function sideFor(tiles, minWidth, half) {
    if (minWidth > half - 8) {
        return "";
    }
    const left = tiles.some(isLeft);
    const right = tiles.some(isRight);
    return left && !right ? "right" : right && !left ? "left" : "right";
}
