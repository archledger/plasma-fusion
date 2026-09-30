/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasma Fusion tablet posture (TABLET.md 3.1): KWin's own tablet-mode state, which is the
    source of truth. Kirigami.Settings.tabletMode alone can start stale inside KWin and then miss
    the next change (TABLET.md F3), so this asks KWin once and then follows its signals:

      - at creation, one asynchronous org.freedesktop.DBus.Properties.GetAll of
        org.kde.KWin.TabletModeManager on org.kde.KWin /org/kde/KWin;
      - then a SignalWatcher on tabletModeChanged(bool) and tabletModeAvailableChanged(bool).

    Until the first answer, or when there is no KWin on the bus (the lock-screen harness, an
    offscreen test), it follows Kirigami.Settings, so KDE_KIRIGAMI_TABLET_MODE=1 still works.
    No polling and no timers. The source is packages/common/FusionTablet.qml;
    tools/build-lib/shared-qml.sh copies it into every package that uses it (do not edit the
    copies). One per applet root, KWin script or lock screen is enough; pass it down:

      FusionTablet { id: tabletState }
      FusionMetrics { id: m; tablet: tabletState.tablet }   // m.touch then follows KWin too

    Touch behaviour is decided per event from eventPoint.device.type, never from `tablet`
    (TABLET.md 2.4 and 3.1): the pen and the mouse keep hover in tablet posture.
*/
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus

Item {
    id: tabletState

    visible: false
    width: 0
    height: 0

    // True while KWin is in tablet mode (the laptop folded, or [Input] TabletMode=on).
    readonly property bool tablet: kwinTabletKnown ? kwinTablet : Kirigami.Settings.tabletMode
    // True while tablet mode can change on its own (a tablet-mode switch or the touch heuristic).
    readonly property bool available: kwinAvailableKnown ? kwinAvailable : Kirigami.Settings.tabletModeAvailable
    // True once KWin answered; false means the Kirigami fallback is in use.
    readonly property bool fromKWin: kwinTabletKnown

    property bool kwinTablet: false
    property bool kwinTabletKnown: false
    property bool kwinAvailable: false
    property bool kwinAvailableKnown: false

    readonly property string service: "org.kde.KWin"
    readonly property string path: "/org/kde/KWin"
    readonly property string iface: "org.kde.KWin.TabletModeManager"

    // Asks KWin for both properties (called once at creation). A signal that arrives before the
    // answer is newer or equal, and D-Bus keeps the order of one sender's messages, so applying
    // both in arrival order is right.
    function refresh(): void {
        DBus.SessionBus.asyncCall({
            "service": tabletState.service,
            "path": tabletState.path,
            "iface": "org.freedesktop.DBus.Properties",
            "member": "GetAll",
            "arguments": [new DBus.string(tabletState.iface)],
            "signature": "(s)"
        }, reply => {
            const props = reply.value;
            if (!props) {
                return;
            }
            if (props.tabletMode !== undefined) {
                tabletState.kwinTablet = props.tabletMode === true;
                tabletState.kwinTabletKnown = true;
            }
            if (props.tabletModeAvailable !== undefined) {
                tabletState.kwinAvailable = props.tabletModeAvailable === true;
                tabletState.kwinAvailableKnown = true;
            }
        }, () => {
            // No KWin on this bus: keep following Kirigami.
        });
    }

    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: tabletState.service
        path: tabletState.path
        iface: tabletState.iface

        function dbustabletModeChanged(value) {
            tabletState.kwinTablet = value === true;
            tabletState.kwinTabletKnown = true;
        }
        function dbustabletModeAvailableChanged(value) {
            tabletState.kwinAvailable = value === true;
            tabletState.kwinAvailableKnown = true;
        }
    }

    Component.onCompleted: refresh()
}
