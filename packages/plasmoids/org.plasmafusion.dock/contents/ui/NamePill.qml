/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.plasma.core as PlasmaCore

// The name pill above the hovered dock item (Main board: padding 5/10, radius 8,
// rgba(12,15,28,.92) fill, 1 px edge, 12 px bold text). It is a separate tooltip
// window so it can sit above the panel; it never takes focus or input.
PlasmaCore.Dialog {
    id: pill

    required property DockPalette pal
    property string text
    // The item whose top edge the pill sits on (horizontally centred on it).
    property Item anchorItem

    type: PlasmaCore.Dialog.Tooltip
    flags: Qt.WindowDoesNotAcceptFocus | Qt.WindowStaysOnTopHint | Qt.WindowTransparentForInput
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Dialog.NoBackground
    visualParent: anchorItem

    // Place the pill; Dialog only positions itself when shown or resized.
    function reposition(): void {
        if (!anchorItem || !anchorItem.Window.window) {
            return;
        }
        const p = anchorItem.mapToGlobal(0, 0);
        x = Math.round(p.x + (anchorItem.width - width) / 2);
        y = Math.round(p.y - height);
    }

    onWidthChanged: if (visible) Qt.callLater(reposition)
    onVisibleChanged: if (visible) Qt.callLater(reposition)

    mainItem: Rectangle {
        // Very long names are elided so the pill never runs off the screen.
        readonly property real maxTextWidth: 320
        implicitWidth: Math.round(Math.min(label.implicitWidth, maxTextWidth)) + 20 + 2
        // CSS line box of Manrope at 12 px (1.366 em) + 5 px padding + 1 px edge, top and bottom.
        implicitHeight: Math.round(label.font.pixelSize * 1.366) + 10 + 2
        width: implicitWidth
        height: implicitHeight
        radius: 8
        color: pill.pal.tipFill
        antialiasing: true

        // CSS draws the border over the background (background-clip: border-box), so the
        // edge is the fill lightened by the border colour, not the wallpaper behind it.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: pill.pal.tipBorder
            antialiasing: true
        }

        Text {
            id: label
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.maxTextWidth)
            elide: Text.ElideRight
            text: pill.text
            color: pill.pal.tipText
            font.family: "Manrope"
            font.pixelSize: 12
            font.weight: Font.Bold
            renderType: Text.QtRendering
        }
    }
}
