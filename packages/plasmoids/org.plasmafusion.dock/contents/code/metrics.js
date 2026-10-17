.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The dock's sizes (board DockSize.dc.html, owner 2026-10-16): Small, Medium (the Main board's
    dock) and Large (the Tablet board's 56 px dock), chosen on the Plasma Fusion settings page
    (the dockSize key; the page also sets the panel to the plate's height). In tablet posture the
    dock keeps its own metrics (TABLET 4.4) at its tabletTile size.

    Each size: the app and button tile, the gap between items, the separator's length and its
    slot (1 px line and a margin on each side), the padding from the plate's sides and bottom,
    the plate (the panel's height with the plain dock frame) and whether the running indicators
    are the tablet's wider ones (6 x 4 dot, 18 x 4 pill, 4 px under the icon).
*/
var SMALL = 0, MEDIUM = 1, LARGE = 2;

var SIZES = [
    { tile: 40, gap: 7, sepLength: 30, sepSlot: 7, sidePad: 10, bottomPad: 12, plate: 60, wideIndicators: false },
    { tile: 48, gap: 8, sepLength: 36, sepSlot: 9, sidePad: 12, bottomPad: 14, plate: 72, wideIndicators: false },
    { tile: 56, gap: 12, sepLength: 40, sepSlot: 13, sidePad: 12, bottomPad: 12, plate: 78, wideIndicators: true },
];

// A dockSize value as one of the three (an unknown one is Medium, today's dock).
function size(value) {
    const n = value === "" || value === null || value === undefined ? MEDIUM : Number(value);
    return n === SMALL || n === LARGE ? n : MEDIUM;
}

// The metrics of SIZE, or in tablet posture the tablet's at TABLETTILE px.
function metrics(sizeValue, tablet, tabletTile) {
    if (tablet) {
        return { tile: tabletTile, gap: 12, sepLength: 40, sepSlot: 13, sidePad: 12, bottomPad: 12, plate: 0, wideIndicators: true };
    }
    return Object.assign({}, SIZES[size(sizeValue)]);
}

// The size of the icon under the pointer for TILE px icons. MAGNIFIEDSIZE is the setting (the
// settings page's +8 / +14 px are 56 / 62, the Medium dock's magnified sizes, as before the
// sizes): its step over 48 px is added to the icons, and below 48 px it shrinks with them, so
// a Small dock's icon does not swell past its neighbours (52 px at +14, 47 at +8). In tablet
// posture the step is 14, as before.
function zoomTarget(tile, magnifiedSize, tablet) {
    if (tablet) {
        return tile + 14;
    }
    const step = Math.max(0, Number(magnifiedSize) - 48);
    return tile + Math.round(step * Math.min(1, tile / 48));
}
