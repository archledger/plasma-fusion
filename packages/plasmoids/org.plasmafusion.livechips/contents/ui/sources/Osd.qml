// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.workspace.dbus as DBus

import "../../code/chips.js" as Chips

// Plasma's own notices for the island (board Island.dc.html, "volume, brightness and Plasma's
// notices"): plasmashell shows every one of them (the volume, the microphone, a player's volume,
// the screen and keyboard brightness, the keyboard layout, the touchpad...) through its Osd object,
// which also sends each as a signal on /org/kde/osdService (plasmashell 6.7.5 shell/osd.cpp:
// osdProgress(icon, percent, maximum, text), osdText(icon, text)). While the top bar is hidden the
// tablet KWin script makes Plasma's own pop-up window transparent on the screen KWin put it on and
// asks that screen's island to show the notice instead ([General] noticeRequest, request()):
// the latest one, and the ones that follow while it shows, for Plasma's own 1.8 s (OsdItem.qml).
Item {
    id: osd

    // The notice the island shows (Chips.notice()), or null.
    property var notice: null
    // The latest notice Plasma sent, with the time it came ({ notice, at }).
    property var latest: null
    // Until when (ms since the epoch) this screen's island shows Plasma's notices: from KWin's
    // request until 1.8 s after the last notice.
    property double showingUntil: 0
    readonly property int timeout: 1800

    function received(n: var): void {
        latest = { notice: n, at: Date.now() };
        if (Date.now() < showingUntil) {
            show(n);
        }
    }
    function show(n: var): void {
        notice = n;
        showingUntil = Date.now() + timeout;
        hold.restart();
    }
    // KWin put Plasma's pop-up on this screen and made it transparent: the notice it shows is the
    // one that just came (Plasma sends it before it shows its window); one that comes a moment
    // after the request is shown as it comes.
    function request(): void {
        showingUntil = Date.now() + timeout;
        if (latest !== null && Date.now() - latest.at < 1000) {
            show(latest.notice);
        } else {
            hold.restart();
        }
    }

    Timer {
        id: hold
        interval: osd.timeout
        onTriggered: osd.notice = null
    }

    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.kde.plasmashell"
        path: "/org/kde/osdService"
        iface: "org.kde.osdService"
        // The D-Bus module's values (a string arrives wrapped, as { value }) convert as their
        // own through String() and Number(), as Chips.notice() takes them.
        function dbusosdProgress(icon, percent, maximum, text) {
            osd.received(Chips.notice(icon, percent, maximum, text));
        }
        function dbusosdText(icon, text) {
            osd.received(Chips.notice(icon, null, null, text));
        }
    }
}
