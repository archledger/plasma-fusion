/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The window pill's drag in tablet posture (board TabletSnap.dc.html): what a release does where
    the finger is, and what a flick of the pill does. Tested by tests/drop.test.js (node).
*/

.pragma library

// The bottom of the work area that sends the app home (the dock's place).
const HOME_BAND = 96;
// A flick: as fast sideways as the home screen's swipe down must be downwards.
const FLICK_SPEED = 800;

// finger: the finger in the screen's coordinates; width: the screen's width; top and bottom: the
// work area's top (below the top bar) and bottom. "" (back in the top bar: nothing), "home",
// "left", "right" (the outer thirds) or "full" (the middle).
function target(finger, width, top, bottom) {
    if (finger.y < top) {
        return "";
    }
    if (finger.y >= bottom - HOME_BAND) {
        return "home";
    }
    if (finger.x < width / 3) {
        return "left";
    }
    if (finger.x > width * 2 / 3) {
        return "right";
    }
    return "full";
}

// The side a flick of the pill puts the app in ("" for a slow or mostly downward move).
function flick(vx, vy) {
    if (Math.abs(vx) < FLICK_SPEED || Math.abs(vx) < Math.abs(vy)) {
        return "";
    }
    return vx > 0 ? "right" : "left";
}

// Whether a window's screen (the task model's ScreenGeometry) is the bar's screen.
function sameScreen(window, bar) {
    return !!window && !!bar && window.x === bar.x && window.y === bar.y
        && window.width === bar.width && window.height === bar.height;
}
