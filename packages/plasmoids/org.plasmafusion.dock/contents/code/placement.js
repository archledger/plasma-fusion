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
// stays 8 px inside it, along the dock and, beside a dock on a side, across it too (one wider than
// room() lies over the dock rather than off the screen).
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
            x = Math.max(screen.x + 8, Math.min(x, screen.x + screen.width - size.width - 8));
        } else {
            x = Math.max(screen.x + 8, Math.min(x, screen.x + screen.width - size.width - 8));
        }
    }
    return { x: Math.round(x), y: Math.round(y) };
}

// The width a pop-up at ANCHOR may take on SCREEN, 8 px inside it: the screen's width on the bottom
// dock, the room beside the anchor (away from the screen's edge) on a dock on the left or right.
function room(anchor, edge, screen) {
    if (edge === "left") {
        return screen.x + screen.width - 8 - (anchor.x + anchor.width);
    }
    if (edge === "right") {
        return anchor.x - (screen.x + 8);
    }
    return screen.width - 16;
}

// A point's place along the row (row coordinates): y on a dock on the left or right, else x.
function along(point, edge) {
    return edge === "left" || edge === "right" ? point.y : point.x;
}

// The task under a point along the row: the first visible one whose span [taskX, taskX + taskW)
// holds it, or -1.
function taskAt(position, taskX, taskW, visible) {
    for (let i = 0; i < taskX.length; ++i) {
        if (visible[i] && position >= taskX[i] && position < taskX[i] + taskW[i]) {
            return i;
        }
    }
    return -1;
}

// Whether a drag of DELTA {x, y} goes away from the dock's EDGE (the launcher drag's direction):
// right from a dock on the left, left from one on the right, up from the bottom dock.
function awayFromEdge(delta, edge) {
    return edge === "left" ? delta.x > 0 : edge === "right" ? delta.x < 0 : delta.y < 0;
}

