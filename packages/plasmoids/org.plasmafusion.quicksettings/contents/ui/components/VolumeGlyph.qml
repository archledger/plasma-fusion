// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import "Icons.js" as Icons

// Speaker with 0-2 waves, or crossed out when muted (FileIcons board, Volume).
LineIcon {
    id: glyph

    required property FusionPalette pal
    property real volume: 1
    property bool muted: false
    property color baseColor: pal.text

    readonly property int waves: muted || volume <= 0 ? -1 : (volume < 0.25 ? 0 : (volume < 0.6 ? 1 : 2))

    color: baseColor
    dimColor: pal.dark ? Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.28) : Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.22)
    path: {
        if (waves < 0) {
            return Icons.speaker + Icons.muteCross;
        }
        if (waves === 0) {
            return Icons.speaker;
        }
        if (waves === 1) {
            return Icons.speaker + Icons.wave1;
        }
        return Icons.speaker + Icons.wave1 + Icons.wave2;
    }
    dimPath: waves === 0 ? Icons.wave1 + Icons.wave2 : (waves === 1 ? Icons.wave2 : "")
}
