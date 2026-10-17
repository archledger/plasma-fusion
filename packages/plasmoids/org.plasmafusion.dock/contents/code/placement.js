.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Where the dock's pop-ups go (the name pill, the window previews; board DockPosition.dc.html):
    above their anchor and centred on it on the bottom dock, beside it and centred on its height
    on a dock on the left or right (the dock places the anchor 12 px off the icon, on the side
    away from the screen's edge).
*/

// The dock's edge from Plasma's location: "left", "right" or "bottom" (every other one).
function edgeOf(location, leftEdge, rightEdge) {
    return location === leftEdge ? "left" : location === rightEdge ? "right" : "bottom";
}

// The top-left corner of a pop-up of SIZE {width, height} at ANCHOR {x, y, width, height} (global
// coordinates) for a dock on EDGE; with SCREEN {x, y, width, height} (its width above 0) the pop-up
// stays 8 px inside it along the dock.
function popupPosition(anchor, size, edge, screen) {
    let x;
    let y;
    if (edge === "left") {
        x = anchor.x + anchor.width;
        y = anchor.y + (anchor.height - size.height) / 2;
    } else if (edge === "right") {
        x = anchor.x - size.width;
        y = anchor.y + (anchor.height - size.height) / 2;
    } else {
        x = anchor.x + (anchor.width - size.width) / 2;
        y = anchor.y - size.height;
    }
    if (screen && screen.width > 0) {
        if (edge === "left" || edge === "right") {
            y = Math.max(screen.y + 8, Math.min(y, screen.y + screen.height - size.height - 8));
        } else {
            x = Math.max(screen.x + 8, Math.min(x, screen.x + screen.width - size.width - 8));
        }
    }
    return { x: Math.round(x), y: Math.round(y) };
}
