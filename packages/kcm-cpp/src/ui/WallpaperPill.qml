/*
    "From wallpaper": a 26 px pill with a dashed 1 px edge (Main board). Chosen, it shows the
    swatches' double ring in the colour taken from the wallpaper.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

T.AbstractButton {
    id: pill

    required property FusionPalette pal
    property bool selected: false
    property color wallpaperColor: "transparent"
    readonly property color ringColor: wallpaperColor.a > 0 ? wallpaperColor : pal.cardSelected

    // CSS box: 10 px padding and the 1 px border on each side.
    implicitWidth: label.implicitWidth + 22
    implicitHeight: 26
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.RadioButton
    Accessible.name: text
    Accessible.checked: selected
    Accessible.onPressAction: pill.clicked()

    QQC2.ToolTip.text: i18nc("@info:tooltip", "Take the accent color from the wallpaper")
    QQC2.ToolTip.visible: hovered
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

    background: Item {
        // Keyboard focus: a ring in the focus colour, outside the selection ring when both show.
        Rectangle {
            visible: pill.visualFocus
            anchors.fill: parent
            anchors.margins: pill.selected ? -7 : -4
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: pill.pal.focusRing
        }
        // Selection: the swatches' double ring, in the wallpaper's colour.
        Rectangle {
            visible: pill.selected
            anchors.fill: parent
            anchors.margins: -4
            radius: height / 2
            color: pill.ringColor
        }
        Rectangle {
            visible: pill.selected
            anchors.fill: parent
            anchors.margins: -2
            radius: height / 2
            color: pill.pal.pageBackground
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: pill.down ? pill.pal.segmentBackground : pill.hovered ? pill.pal.segmentHover : "transparent"
        }
        // CSS border: 1px dashed (2 px dashes, 1 px gaps), painted like the browser does
        // (QPainter, antialiased, on the pixel grid inside the box).
        Canvas {
            id: edge
            anchors.fill: parent
            readonly property color strokeColor: pill.selected ? pill.ringColor : pill.pal.pillBorder
            readonly property bool dashed: !pill.selected
            onStrokeColorChanged: requestPaint()
            onDashedChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const r = (height - 1) / 2;
                ctx.lineWidth = 1;
                ctx.strokeStyle = strokeColor;
                if (dashed) {
                    ctx.setLineDash([2, 1]);
                }
                ctx.beginPath();
                ctx.moveTo(0.5 + r, 0.5);
                ctx.lineTo(width - 0.5 - r, 0.5);
                ctx.arc(width - 0.5 - r, 0.5 + r, r, -Math.PI / 2, Math.PI / 2, false);
                ctx.lineTo(0.5 + r, height - 0.5);
                ctx.arc(0.5 + r, 0.5 + r, r, Math.PI / 2, 3 * Math.PI / 2, false);
                ctx.closePath();
                ctx.stroke();
            }
        }
    }

    contentItem: Item {
        Text {
            id: label
            anchors.centerIn: parent
            text: pill.text
            font.family: pill.pal.family
            font.pointSize: 8.625 // 11.5 px (pixelSize is an integer)
            font.weight: Font.Bold
            color: pill.pal.label
        }
    }
}
