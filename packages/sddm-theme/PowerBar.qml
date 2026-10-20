/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * The board's power buttons (Login.dc.html, bottom right): Sleep, Restart and the red Shut down,
 * 44 px circles 18 apart with 11.5/700 labels. Each is shown only when the daemon allows it
 * (sddm.canSuspend/canReboot/canPowerOff) and calls its method (docs/THEMING.md).
 * The glyphs are drawn on Canvas (QtQuick core) so the theme needs no icon or shape module.
 */

import QtQuick 2.15
import "palette.js" as Palette

Item {
    id: power
    width: column.width
    height: column.height

    Row {
        id: column
        spacing: 18

        PowerButton {
            label: qsTr("Sleep")
            visible: sddm.canSuspend
            glyph: "sleep"
            onTriggered: sddm.suspend()
        }
        PowerButton {
            label: qsTr("Restart")
            visible: sddm.canReboot
            glyph: "restart"
            onTriggered: sddm.reboot()
        }
        PowerButton {
            label: qsTr("Shut down")
            visible: sddm.canPowerOff
            glyph: "power"
            danger: true
            onTriggered: sddm.powerOff()
        }
    }

    component PowerButton: Item {
        id: button
        property string label: ""
        property string glyph: ""
        property bool danger: false
        signal triggered()
        width: 52
        height: 66

        Rectangle {
            Accessible.name: button.label
            Accessible.role: Accessible.Button
            activeFocusOnTab: true
            Keys.onReturnPressed: button.triggered()
            Keys.onEnterPressed: button.triggered()
            Keys.onSpacePressed: button.triggered()
            Accessible.onPressAction: button.triggered()
            anchors.horizontalCenter: parent.horizontalCenter
            width: 44
            height: 44
            radius: 22
            color: button.danger ? Palette.danger : Palette.fill
            border.color: activeFocus ? Palette.accent : (button.danger ? Palette.danger : Palette.stroke)
            border.width: activeFocus ? 2 : 1

            Canvas {
                id: canvas
                anchors.centerIn: parent
                width: 18
                height: 18
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.strokeStyle = button.danger ? "#ffffff" : Palette.ink;
                    ctx.fillStyle = button.danger ? "#ffffff" : Palette.ink;
                    ctx.lineWidth = 1.8;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    const c = 9;
                    if (button.glyph === "power") {
                        // The board's path M12 3v9 M6.3 6.3a8 8 0 1 0 11.4 0 at 24 -> 18
                        ctx.beginPath();
                        ctx.moveTo(c, 2.25);
                        ctx.lineTo(c, 9);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.arc(c, c, 6, Math.PI * 0.75 - Math.PI, Math.PI * 0.25);
                        ctx.stroke();
                    } else if (button.glyph === "restart") {
                        // The board's path M20 12a8 8 0 1 1-2.3-5.7 M20 4v5h-5
                        ctx.beginPath();
                        ctx.arc(c, c, 6, Math.PI * 0.25, Math.PI * 1.85);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(c + 5.2, c - 5.2);
                        ctx.lineTo(c + 5.2, c - 1.2);
                        ctx.lineTo(c + 1.6, c - 3.4);
                        ctx.closePath();
                        ctx.fill();
                    } else {
                        // Sleep: the board's moon (a crescent of two circles)
                        ctx.globalCompositeOperation = "source-over";
                        ctx.beginPath();
                        ctx.arc(c, c, 6, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.globalCompositeOperation = "destination-out";
                        ctx.beginPath();
                        ctx.arc(c + 3.4, c - 2.6, 5.4, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.globalCompositeOperation = "source-over";
                    }
                }
                Component.onCompleted: requestPaint()
            }
            MouseArea {
                anchors.fill: parent
                onClicked: button.triggered()
            }
        }
        Text {
            anchors.top: parent.top
            anchors.topMargin: 50
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: Palette.bodyFont
            font.pixelSize: 12
            font.weight: Font.Bold
            color: Palette.inkSoft
            text: button.label
        }
    }
}
