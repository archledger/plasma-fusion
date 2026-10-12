// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.private.batterymonitor
import org.kde.plasma.workspace.dbus as DBus

import "../global"
import "../../code/keepawake.js" as Timed

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
    onActiveChanged: {
        Instances.keepAwakeTimeout.stop();
        Instances.keepAwakePending = false;
        // Turned off, here, by the time running out or elsewhere (the hidden battery applet shares
        // the state): a timer set before has nothing left to end.
        if (!active) {
            Instances.keepAwakeUntil = 0;
        }
        tick();
    }
    Connections {
        target: Instances.keepAwakeTimeout
        // A timed request that never took effect leaves no timer behind for the next one.
        function onTriggered() {
            if (!keepAwake.active) {
                Instances.keepAwakeUntil = 0;
            }
        }
    }
    function toggle(reason: string): void {
        if (!available || Instances.keepAwakePending) {
            return;
        }
        Instances.keepAwakePending = true;
        Instances.keepAwakeTimeout.restart();
        if (active) {
            control.uninhibit();
        } else {
            Instances.keepAwakeUntil = 0;
            control.inhibit(reason);
        }
    }

    // Keep awake for a while (F7): until `until` (ms since the epoch), or until turned off (0). The
    // end is kept in Instances, so every widget shows it, the timer runs with the sheet closed,
    // and whichever widget sees the time first turns it off (one request at a time, as above).
    // Plasma's own manual inhibition ends with the plasmashell process; so does the timer, which is
    // not restored at the next start (nor is "until turned off").
    readonly property double until: active ? Instances.keepAwakeUntil : 0
    function keepAwakeUntil(reason: string, until: double): void {
        if (!available || Instances.keepAwakePending) {
            return;
        }
        Instances.keepAwakeUntil = Math.max(0, until);
        if (!active) {
            Instances.keepAwakePending = true;
            Instances.keepAwakeTimeout.restart();
            control.inhibit(reason);
        }
    }
    // The clock as last looked at: the minutes left follow it.
    property double now: Date.now()
    readonly property int minutesLeft: until > 0 ? Timed.minutesLeft(now, until) : 0
    onUntilChanged: tick()
    function tick(): void {
        now = Date.now();
        if (!active || until <= 0) {
            ticker.stop();
            return;
        }
        const wait = Timed.nextCheck(now, until);
        if (wait > 0) {
            ticker.interval = wait;
            ticker.restart();
        } else if (!Instances.keepAwakePending) {
            Instances.keepAwakePending = true;
            Instances.keepAwakeTimeout.restart();
            control.uninhibit();
        } else {
            // Another request is on its way (another widget's, for the same end): look again.
            ticker.interval = 1000;
            ticker.restart();
        }
    }
    // Qt's timers stop while the computer is suspended; the end is a wall-clock time, so a late
    // tick still ends it, at most a minute after the resume.
    Timer {
        id: ticker
        onTriggered: keepAwake.tick()
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
