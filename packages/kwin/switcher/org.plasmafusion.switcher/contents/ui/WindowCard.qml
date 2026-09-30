/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWin

// One window of the switcher grid (AltTab board): padding 10, radius 18, a 118 px live preview
// with radius 10 and a 1 px edge, then the app icon (24) with the app name and window title.
// Selected: accent fill .16 and a 2 px ring. The caption (icon, gap and text) follows the
// user's text size; the preview and the paddings do not.
Item {
    id: card

    property FusionPalette pal
    property FusionMetrics metrics
    property var windowId
    property var icon
    property string appName
    property string title
    property bool selected: false
    property bool closeable: false
    property int thumbnailHeight: 118

    signal activated()
    signal closeRequested()

    Accessible.role: Accessible.ListItem
    Accessible.name: title.length > 0 ? appName + ", " + title : appName
    Accessible.selected: selected

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: card.selected ? card.pal.selectedFill
                             : (pointer.containsMouse ? card.pal.hoverFill : "transparent")
    }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: "transparent"
        border.width: 2
        border.color: card.pal.ring
        visible: card.selected
    }

    Item {
        id: thumbBox
        x: 10
        y: 10
        width: card.width - 20
        height: card.thumbnailHeight

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: card.pal.thumbFill
        }

        // Shown while the preview has no content yet (and for windows KWin cannot render).
        Kirigami.Icon {
            anchors.centerIn: parent
            width: 48
            height: 48
            source: card.icon
            opacity: 0.8
        }

        // The preview fills the box like CSS "cover", top aligned, clipped to the rounded box.
        Item {
            id: thumbClip
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: thumbMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            KWin.WindowThumbnail {
                id: thumbnail
                readonly property real sourceWidth: Math.max(1, thumbnail.implicitWidth)
                readonly property real sourceHeight: Math.max(1, thumbnail.implicitHeight)
                readonly property real scale_: Math.max(thumbBox.width / sourceWidth, thumbBox.height / sourceHeight)
                wId: card.windowId
                width: Math.ceil(thumbnail.sourceWidth * thumbnail.scale_)
                height: Math.ceil(thumbnail.sourceHeight * thumbnail.scale_)
                x: Math.round((thumbBox.width - thumbnail.width) / 2)
                y: 0
            }
        }

        Rectangle {
            id: thumbMask
            anchors.fill: parent
            radius: 10
            visible: false
            layer.enabled: true
            layer.smooth: true
        }

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: "transparent"
            border.width: 1
            border.color: card.pal.thumbEdge
        }

        // Close button, only while the pointer is over the card.
        Rectangle {
            id: closeButton
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            width: 22
            height: 22
            radius: 11
            visible: card.closeable && (pointer.containsMouse || closeArea.containsMouse)
            color: closeArea.containsMouse ? "#d9434b" : Qt.rgba(0, 0, 0, 0.45)

            Canvas {
                anchors.centerIn: parent
                width: 10
                height: 10
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = "#ffffff";
                    ctx.lineWidth = 1.6;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.moveTo(1.5, 1.5);
                    ctx.lineTo(8.5, 8.5);
                    ctx.moveTo(8.5, 1.5);
                    ctx.lineTo(1.5, 8.5);
                    ctx.stroke();
                }
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: card.closeRequested()
            }
        }
    }

    Item {
        id: caption
        x: 10
        y: thumbBox.y + thumbBox.height + 10
        width: card.width - 20
        height: Math.max(appIcon.height, texts.implicitHeight)

        Kirigami.Icon {
            id: appIcon
            anchors.verticalCenter: parent.verticalCenter
            width: card.metrics.px(24)
            height: width
            source: card.icon
        }

        Column {
            id: texts
            anchors.verticalCenter: parent.verticalCenter
            x: appIcon.width + card.metrics.px(8)
            width: parent.width - x

            Text {
                width: parent.width
                text: card.appName
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
                font.family: card.metrics.family
                font.pointSize: card.metrics.font(13) * 0.75
                font.weight: Font.ExtraBold
                color: card.pal.text
                renderType: Text.QtRendering
            }

            Text {
                width: parent.width
                text: card.title
                visible: text.length > 0
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
                font.family: card.metrics.family
                font.pointSize: card.metrics.font(11.5) * 0.75
                color: card.pal.textMuted
                renderType: Text.QtRendering
            }
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                if (card.closeable) {
                    card.closeRequested();
                }
            } else {
                card.activated();
            }
        }
    }
}
