/*
    SPDX-FileCopyrightText: 2018 David Edmundson <davidedmundson@kde.org>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

//written as a library to share knowledge of when a key was pressed
//between the multiple views, so pressing a key on one cancels all timers

var callbacks = [];

function addCancelAutoTriggerCallback(callback) {
    callbacks.push(callback);
}

// Plasma Fusion: a screen's root takes its callback out when it goes (an output unplugged while
// the greeter is open). Upstream keeps it, and calling it then throws on the deleted timer.
function removeCancelAutoTriggerCallback(callback) {
    callbacks = callbacks.filter(function(c) {
        return c !== callback;
    });
}

function cancelAutoTrigger() {
    callbacks.slice().forEach(function(c) {
        if (!c) {
            return;
        }
        // Plasma Fusion: one callback that fails must not keep the other screens counting down
        // to the log-out or shut-down after a key press.
        try {
            c();
        } catch (error) {
            console.warn("logout: a count-down could not be stopped:", error);
        }
    });
}
