// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import "Icons.js" as Icons

// Battery outline filled to the charge level; lightning bolt while charging,
// warning colour at 30 % and below, danger colour at 10 % and below.
LineIcon {
    id: glyph

    required property FusionPalette pal
    property int percent: 100
    property bool charging: false
    property color baseColor: pal.text

    readonly property bool low: !charging && percent <= 10
    readonly property bool warn: !charging && percent <= 30

    size: 18
    color: low ? pal.danger : baseColor
    path: Icons.batteryOutline
    fillPath: charging ? Icons.batteryBolt : Icons.batteryLevel(Math.max(1.4, 12 * Math.min(100, Math.max(0, percent)) / 100))
    fillColor: charging ? pal.charging : (low ? pal.danger : (warn ? pal.warning : baseColor))
}
