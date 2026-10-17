// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Shapes
import QtQuick.Window

// One screen's overlay (CopyText board): the screen as it was at the click, under the veil; the
// box drawn on it is clear with a 2 px accent edge (radius 4) and a soft accent halo; the hint in
// the island's black under the bar, gone once the drag starts. As the drag ends the box is chosen;
// Esc, or a click without a drag, cancels.
Window {
    id: overlay

    required property string screenName
    required property url picture

    signal chosen(string screenName, rect area)
    signal cancelled()

    // The box being drawn, in this window's logical pixels; from: where the drag started.
    property point from: Qt.point(0, 0)
    property rect box: Qt.rect(0, 0, 0, 0)
    readonly property bool drawing: box.width > 0 || box.height > 0
    readonly property color veil: Qt.rgba(8 / 255, 11 / 255, 22 / 255, 0.45)
    readonly property color accent: "#5b9dff"

    color: "#000000"
    flags: Qt.FramelessWindowHint

    Image {
        anchors.fill: parent
        source: overlay.picture
        cache: false
        smooth: true
    }

    // The veil everywhere but the box.
    Rectangle {
        width: overlay.width
        height: overlay.drawing ? overlay.box.y : overlay.height
        color: overlay.veil
    }
    Rectangle {
        visible: overlay.drawing
        y: overlay.box.y + overlay.box.height
        width: overlay.width
        height: overlay.height - y
        color: overlay.veil
    }
    Rectangle {
        visible: overlay.drawing
        y: overlay.box.y
        width: overlay.box.x
        height: overlay.box.height
        color: overlay.veil
    }
    Rectangle {
        visible: overlay.drawing
        x: overlay.box.x + overlay.box.width
        y: overlay.box.y
        width: overlay.width - x
        height: overlay.box.height
        color: overlay.veil
    }

    // The halo, then the edge, just outside the box.
    Rectangle {
        objectName: "halo"
        visible: overlay.drawing
        x: overlay.box.x - 6
        y: overlay.box.y - 6
        width: overlay.box.width + 12
        height: overlay.box.height + 12
        radius: 8
        color: "transparent"
        border.width: 4
        border.color: Qt.rgba(91 / 255, 157 / 255, 1, 0.22)
    }
    Rectangle {
        objectName: "edge"
        visible: overlay.drawing
        x: overlay.box.x - 2
        y: overlay.box.y - 2
        width: overlay.box.width + 4
        height: overlay.box.height + 4
        radius: 4
        color: "transparent"
        border.width: 2
        border.color: overlay.accent
    }

    // The hint: the island's black and type, centred 46 px from the top (under a 34 px bar).
    Rectangle {
        objectName: "hint"
        visible: !overlay.drawing
        anchors.horizontalCenter: parent.horizontalCenter
        y: 46
        height: 32
        width: hint.implicitWidth + 24
        radius: 16
        color: "#000000"
        Row {
            id: hint
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Shape {
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    scale: Qt.size(16 / 24, 16 / 24)
                    strokeColor: "#ffffff"
                    strokeWidth: 1.8
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg {
                        path: "M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M8.5 9h7M8.5 12h7M8.5 15h4.5"
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: i18nc("@info the hint over the still screen", "Draw a box around the text")
                color: "#ffffff"
                font.pixelSize: 13
                font.weight: Font.Bold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: i18nc("@info the hint over the still screen", "Esc cancels")
                color: Qt.rgba(1, 1, 1, 0.62)
                font.pointSize: 9.375 // 12.5 px at 96 dpi (pixelSize takes whole pixels)
                font.weight: Font.DemiBold
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        Accessible.role: Accessible.Canvas
        Accessible.name: i18nc("@info:whatsthis", "Draw a box around the text to copy it; Esc cancels")
        onPressed: mouse => {
            overlay.from = Qt.point(mouse.x, mouse.y);
            overlay.box = Qt.rect(mouse.x, mouse.y, 0, 0);
        }
        onPositionChanged: mouse => {
            const x = Math.max(0, Math.min(overlay.from.x, mouse.x));
            const y = Math.max(0, Math.min(overlay.from.y, mouse.y));
            overlay.box = Qt.rect(x, y, Math.min(overlay.width, Math.max(overlay.from.x, mouse.x)) - x,
                                  Math.min(overlay.height, Math.max(overlay.from.y, mouse.y)) - y);
        }
        onReleased: {
            if (overlay.box.width >= 4 && overlay.box.height >= 4) {
                overlay.chosen(overlay.screenName, overlay.box);
            } else {
                overlay.cancelled();
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: overlay.cancelled()
    }
}
