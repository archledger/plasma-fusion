// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma Singleton

import QtQuick

// Every quick settings widget of this plasmashell (one per top bar: each screen's bar has one,
// owner decision 2026-10-09). The widgets share this object (plasmashell loads all applets into one
// QML engine, as the stock notifications applet's Globals relies on), so they can tell which of
// them does a job once for the session: the `leader`, the widget on the lowest screen number (the
// primary screen is 0), else the first to come. When it goes, the next one takes over.
QtObject {
    // The widgets' root items (main.qml), in the order they came.
    property var items: []
    // A keep-awake request is on its way (KeepAwake.qml): the native monitor is shared by every
    // widget and keeps one pair of cookies, so one request at a time across all of them.
    property bool keepAwakePending: false
    // The hotspot runs (Network.qml): plasma-nm's handler of a widget only knows of a hotspot it
    // started or found running when it was made, so the widgets share what their handlers see.
    property bool hotspotActive: false
    // Its one timeout (a widget's own timer could end another widget's request early).
    readonly property Timer keepAwakeTimeout: Timer {
        interval: 5000
        onTriggered: keepAwakePending = false
    }

    readonly property var leader: {
        let best = null;
        let bestRank = Infinity;
        for (let i = 0; i < items.length; ++i) {
            const screen = items[i].screenIndex;
            const rank = screen >= 0 ? screen : 1000 + i;
            if (rank < bestRank) {
                best = items[i];
                bestRank = rank;
            }
        }
        return best;
    }

    function adopt(item: var): void {
        if (items.indexOf(item) === -1) {
            items = items.concat([item]);
        }
    }
    function forget(item: var): void {
        items = items.filter(i => i !== item);
    }
    // The widget on the screen with this name (KWin's output name), or null.
    function onScreen(name: string): var {
        return name === "" ? null : items.find(i => i.screenName === name) ?? null;
    }
}
