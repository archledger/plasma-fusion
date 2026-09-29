// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.networkmanagement as PlasmaNM

// Lock board status chip: the network state as the board's line icon. Loaded through a Loader
// so that a system without plasma-nm still gets a working lock screen.
Item {
    id: indicator

    readonly property string iconName: connectionIcon.connectionIcon
    readonly property bool wireless: iconName.startsWith("network-wireless") && !iconName.includes("bluetooth")
    readonly property bool wired: iconName.startsWith("network-wired")
    readonly property bool disconnected: iconName.includes("disconnected") || iconName === "network-unavailable"
                                         || iconName.startsWith("network-flightmode") || iconName.length === 0
    readonly property int bars: {
        const m = iconName.match(/-(\d+)(-|$)/);
        if (!m) {
            return disconnected ? 0 : 3;
        }
        const level = parseInt(m[1]);
        return level >= 70 ? 3 : level >= 40 ? 2 : level >= 10 ? 1 : 0;
    }
    readonly property string accessibleName: {
        if (disconnected) {
            return i18nd("plasma_shell_org.plasmafusion.lockshell", "Network disconnected");
        }
        if (wired) {
            return i18nd("plasma_shell_org.plasmafusion.lockshell", "Wired network connected");
        }
        return i18nd("plasma_shell_org.plasmafusion.lockshell", "Wi-Fi connected");
    }

    // Whether there is something to show (the loader decides the visibility from this; an
    // item's own "visible" is always false while its parent is hidden).
    readonly property bool available: iconName.length > 0 && !iconName.startsWith("network-mobile")

    implicitWidth: 17
    implicitHeight: 17

    Accessible.role: Accessible.Indicator
    Accessible.name: accessibleName

    PlasmaNM.ConnectionIcon {
        id: connectionIcon
    }

    LineIcon {
        anchors.centerIn: parent
        size: 17
        visible: !indicator.wired
        path: {
            const parts = [PfStyle.iconWifiDot];
            if (indicator.bars >= 1) parts.push(PfStyle.iconWifiArc1);
            if (indicator.bars >= 2) parts.push(PfStyle.iconWifiArc2);
            if (indicator.bars >= 3) parts.push(PfStyle.iconWifiArc3);
            if (indicator.disconnected) parts.push(PfStyle.iconSlash);
            return parts.join("");
        }
        dimPath: {
            const parts = [];
            if (indicator.bars < 1) parts.push(PfStyle.iconWifiArc1);
            if (indicator.bars < 2) parts.push(PfStyle.iconWifiArc2);
            if (indicator.bars < 3) parts.push(PfStyle.iconWifiArc3);
            return parts.join("");
        }
    }
    LineIcon {
        anchors.centerIn: parent
        size: 17
        visible: indicator.wired
        path: PfStyle.iconWired + (indicator.disconnected ? PfStyle.iconSlash : "")
    }
}
