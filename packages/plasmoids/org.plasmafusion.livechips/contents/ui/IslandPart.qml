// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami

import "../code/chips.js" as Chips

// A compact part of the island (board Island.dc.html): the leading part names the thing (the app's
// icon, the recording's red dot, Keep awake's cup, the music's cover), the trailing part shows its
// state (the privacy dots, the recording's time, the time left, the music's levels). In the bubble
// only the leading part shows. 20 px leading parts sit concentric in the island's 6 px margins.
Item {
    id: part

    required property Island island
    // "privacy", "recording", "keepawake" or "music"
    required property string item
    required property bool leading

    readonly property real unit: island.metrics.px(20)
    readonly property var firstRow: island.rows.length > 0 ? island.rows[0] : null
    readonly property var media: island.media

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    Item {
        id: content
        anchors.centerIn: parent
        implicitWidth: part.leading ? part.unit : trailingRow.implicitWidth
        implicitHeight: part.unit

        // ---- leading
        // The app using the camera, microphone or screen; the kind's glyph when no icon is known.
        // Kirigami.Icon's valid only says a source is set (6.31: an unknown name shows its
        // "unknown" icon); its status says whether the theme has the icon.
        Kirigami.Icon {
            id: appIcon
            readonly property bool found: status === Kirigami.Icon.Ready
            anchors.fill: parent
            visible: part.leading && part.item === "privacy" && found
            source: part.firstRow ? Chips.iconGuess(part.firstRow.app) : ""
        }
        LineIcon {
            anchors.centerIn: parent
            visible: part.leading && part.item === "privacy" && !appIcon.found
            path: Chips.GLYPHS[part.island.content.dots[0] || "camera"] || ""
            color: part.island.glyphColor(part.island.content.dots[0] || "")
            size: part.island.metrics.px(16)
        }
        Rectangle {
            anchors.fill: parent
            visible: part.leading && part.item === "recording"
            radius: width / 2
            color: Qt.rgba(217 / 255, 67 / 255, 75 / 255, 0.35)
            Rectangle {
                anchors.centerIn: parent
                width: part.island.metrics.px(8)
                height: width
                radius: width / 2
                color: part.island.glyphColor("recording")
            }
        }
        LineIcon {
            anchors.centerIn: parent
            visible: part.leading && part.item === "keepawake"
            path: Chips.GLYPHS.keepawake
            color: "#ffffff"
            size: part.island.metrics.px(16)
        }
        // The cover (the player's icon without one); round in the bubble.
        Kirigami.ShadowedImage {
            anchors.fill: parent
            visible: part.leading && part.item === "music" && part.media !== null && part.media.artUrl !== ""
            source: part.media ? part.media.artUrl : ""
            radius: part.parent && part.parent.width === part.parent.height ? width / 2 : part.island.metrics.px(6)
            fillMode: Image.PreserveAspectCrop
        }
        Kirigami.Icon {
            anchors.fill: parent
            visible: part.leading && part.item === "music" && (part.media === null || part.media.artUrl === "")
            source: part.media && part.media.iconName !== "" ? part.media.iconName : "audio-x-generic"
        }

        // ---- trailing
        Row {
            id: trailingRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            visible: !part.leading
            spacing: part.island.metrics.px(4)

            Repeater {
                model: !part.leading && part.item === "privacy" ? part.island.content.dots : []
                delegate: Rectangle {
                    required property string modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: part.island.metrics.px(8)
                    height: width
                    radius: width / 2
                    color: part.island.glyphColor(modelData)
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !part.leading && (part.item === "recording" || part.item === "keepawake")
                // Names and times from other apps: plain text.
                textFormat: Text.PlainText
                text: part.item === "recording" ? (part.island.recording ? part.island.recording.time : "")
                    : part.island.leftText(part.island.keepAwakeLeft)
                color: part.item === "recording" ? part.island.glyphColor("recording") : "#ffffff"
                font.family: part.island.metrics.displayFamily
                font.weight: Font.DemiBold
                font.pixelSize: part.island.metrics.font(13)
            }
            // The music's levels in the cover's colour (still: no endless animation).
            Row {
                anchors.verticalCenter: parent.verticalCenter
                visible: !part.leading && part.item === "music"
                spacing: part.island.metrics.px(2)
                Repeater {
                    model: [6, 12, 9, 14]
                    delegate: Rectangle {
                        required property int modelData
                        anchors.verticalCenter: parent.verticalCenter
                        width: part.island.metrics.px(3)
                        height: part.island.metrics.px(modelData)
                        radius: part.island.metrics.px(2)
                        color: "#f2a65a"
                    }
                }
            }
        }
    }
}
