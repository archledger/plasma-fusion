// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import "Icons.js" as Icons

// Network status icon with the FileIcons board's signal levels: inactive arcs
// are drawn at 28 % (22 % on light), poor signal in the warning colour.
LineIcon {
    id: glyph

    required property FusionPalette pal
    // "wifi", "wired", "mobile", "airplane", "wifi-off", "wifi-idle", "none"
    property string kind: "wifi"
    // 1 poor .. 4 excellent
    property int level: 4
    property color baseColor: pal.text

    color: kind === "wifi" && level <= 1 ? pal.warning : baseColor
    dimColor: pal.dark ? Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.28) : Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.22)

    path: {
        switch (kind) {
        case "wired":
            return Icons.wired;
        case "airplane":
            return Icons.airplane;
        case "wifi-off":
            return Icons.slash;
        case "wifi-idle":
            return "";
        case "mobile":
        case "wifi":
            if (level >= 4) {
                return Icons.wifi;
            }
            if (level === 3) {
                return Icons.wifiArc2 + Icons.wifiArc3 + Icons.wifiDot;
            }
            if (level === 2) {
                return Icons.wifiArc3 + Icons.wifiDot;
            }
            return Icons.wifiDot;
        default:
            return Icons.slash;
        }
    }
    dimPath: {
        switch (kind) {
        case "wired":
        case "airplane":
            return "";
        case "wifi":
        case "mobile":
            if (level >= 4) {
                return "";
            }
            if (level === 3) {
                return Icons.wifiArc1;
            }
            if (level === 2) {
                return Icons.wifiArc1 + Icons.wifiArc2;
            }
            return Icons.wifiArc1 + Icons.wifiArc2 + Icons.wifiArc3;
        default:
            return Icons.wifi;
        }
    }
}
