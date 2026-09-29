// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kdeconnect as KDEConnect

// Paired and reachable KDE Connect devices.
Item {
    id: phone

    readonly property int connectedCount: connected.count
    readonly property string deviceName: connectedCount > 0 ? String(connected.data(connected.index(0, 0), Qt.DisplayRole) || "") : ""

    KDEConnect.DevicesModel {
        id: connected
        displayFilter: KDEConnect.DevicesModel.Paired | KDEConnect.DevicesModel.Reachable
    }
}
