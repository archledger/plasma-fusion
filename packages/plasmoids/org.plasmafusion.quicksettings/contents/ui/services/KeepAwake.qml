// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.private.batterymonitor
import org.kde.plasma.workspace.dbus as DBus

import "../global"

// The same manual inhibition as Plasma's battery applet. The native monitor owns both the sleep
// and ScreenSaver cookies, shares the state across applets, and releases them at session exit.
Item {
    id: keepAwake

    readonly property bool available: power.registered && screenSaver.registered
    readonly property bool active: available && control.isManuallyInhibited
    readonly property var inhibitors: control.requestedInhibitions
    function setAllowed(appName: string, reason: string, allowed: bool): void {
        if (available) { control.setInhibitionAllowed(appName, reason, allowed); }
    }

    // One request at a time, across every quick settings widget (Instances): the native monitor
    // is shared and keeps one pair of cookies, so a second inhibit before the first one's reply
    // replaced them and left an inhibition nothing could release. A request is pending until the
    // state changes (or 5 s pass).
    readonly property bool pending: Instances.keepAwakePending
    onActiveChanged: Instances.keepAwakePending = false
    Timer {
        id: pendingTimeout
        interval: 5000
        onTriggered: Instances.keepAwakePending = false
    }
    function toggle(reason: string): void {
        if (!available || Instances.keepAwakePending) {
            return;
        }
        Instances.keepAwakePending = true;
        pendingTimeout.restart();
        if (active) {
            control.uninhibit();
        } else {
            control.inhibit(reason);
        }
    }

    InhibitionControl {
        id: control
        isSilent: true
    }
    DBus.DBusServiceWatcher {
        id: power
        busType: DBus.BusType.Session
        watchedService: "org.kde.Solid.PowerManagement"
    }
    DBus.DBusServiceWatcher {
        id: screenSaver
        busType: DBus.BusType.Session
        watchedService: "org.freedesktop.ScreenSaver"
    }
}
