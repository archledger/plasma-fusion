// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.private.battery

// Battery charge (Solid / UPower), the same model the Power and Battery applet uses.
Item {
    id: battery

    readonly property bool present: control.hasInternalBatteries
    readonly property int percent: control.percent
    readonly property bool pluggedIn: control.pluggedIn
    readonly property bool charging: control.state === BatteryControlModel.Charging
    readonly property bool full: control.pluggedIn && control.state === BatteryControlModel.FullyCharged
    readonly property real remainingMsec: control.smoothedRemainingMsec

    BatteryControlModel {
        id: control
    }
}
