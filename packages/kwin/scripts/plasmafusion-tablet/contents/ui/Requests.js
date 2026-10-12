// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// The output a swipe from the right edge opens quick settings on: the built-in screen, which is the
// touch screen of a convertible, else KWin's active one (it follows the pointer or focus, not the
// finger). `screens` are KWin outputs (`name`), `isInternal` tells a built-in one.
function swipeOutput(screens, isInternal, active) {
    for (let i = 0; i < screens.length; ++i) {
        if (isInternal(screens[i])) {
            return String(screens[i].name);
        }
    }
    return active ? String(active.name) : "";
}

// Quick settings' openRequest text, "<mode>:<nonce>[:<output>]" (its contents/code/requests.js).
function openRequest(mode, nonce, output) {
    return mode + ":" + nonce + (output ? ":" + output : "");
}
