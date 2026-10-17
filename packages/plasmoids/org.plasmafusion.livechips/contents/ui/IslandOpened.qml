// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../code/chips.js" as Chips

// The opened island (board Island.dc.html), an enlarged version of the compact one that keeps the
// parts where they were: for the privacy kinds a row for each app or login (its icon, what it
// uses with the dots, and Mute, Stop sharing or End); for a recording its time and Stop; for the
// music its cover, title, where it is and play, pause and skip. White on black, 30 px buttons,
// rounded parts inside radius 14 (concentric in the 14 px margins).
ColumnLayout {
    id: opened

    required property Island island

    readonly property string item: island.opened
    readonly property real unit: island.metrics.px(40)
    readonly property color sub: Qt.rgba(1, 1, 1, 0.62)
    readonly property var media: island.media

    spacing: island.metrics.px(8)
    focus: true

    component IslandButton: Rectangle {
        id: button
        property string text
        property color ink: "#ffffff"
        property color fill: Qt.rgba(1, 1, 1, 0.16)
        signal clicked()
        implicitWidth: label.implicitWidth + 2 * opened.island.metrics.px(14)
        implicitHeight: opened.island.metrics.px(30)
        radius: height / 2
        color: mouse.pressed ? Qt.darker(fill, 1.2) : fill
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: clicked()
        Keys.onSpacePressed: clicked()
        Keys.onReturnPressed: clicked()
        Text {
            id: label
            anchors.centerIn: parent
            text: button.text
            color: button.ink
            font.family: opened.island.metrics.family
            font.weight: Font.ExtraBold
            font.pixelSize: opened.island.metrics.font(12)
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            onClicked: button.clicked()
        }
    }

    // ---- privacy: a row for each app or login
    Repeater {
        model: opened.item === "privacy" ? opened.island.rows : []
        delegate: RowLayout {
            id: row
            required property var modelData
            Layout.fillWidth: true
            Layout.minimumHeight: opened.island.metrics.px(56)
            spacing: opened.island.metrics.px(12)

            Item {
                Layout.preferredWidth: opened.unit
                Layout.preferredHeight: opened.unit
                Kirigami.Icon {
                    id: rowIcon
                    anchors.fill: parent
                    visible: row.modelData.login === "" && valid
                    source: row.modelData.login === "" ? Chips.iconGuess(row.modelData.app) : ""
                }
                Rectangle {
                    anchors.fill: parent
                    visible: !rowIcon.visible
                    radius: width / 2
                    color: Qt.rgba(1, 1, 1, 0.12)
                    LineIcon {
                        anchors.centerIn: parent
                        path: Chips.GLYPHS[row.modelData.kinds[0]] || ""
                        color: opened.island.glyphColor(row.modelData.kinds[0])
                        size: opened.island.metrics.px(18)
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: opened.island.metrics.px(3)
                Text {
                    Layout.fillWidth: true
                    // Names from other apps and from logins: plain text.
                    textFormat: Text.PlainText
                    text: row.modelData.app || i18nc("@info an unnamed app", "An app")
                    elide: Text.ElideRight
                    color: "#ffffff"
                    font.family: opened.island.metrics.family
                    font.weight: Font.ExtraBold
                    font.pixelSize: opened.island.metrics.font(14)
                }
                RowLayout {
                    spacing: opened.island.metrics.px(6)
                    Repeater {
                        model: row.modelData.kinds
                        delegate: Rectangle {
                            required property string modelData
                            Layout.preferredWidth: opened.island.metrics.px(6)
                            Layout.preferredHeight: opened.island.metrics.px(6)
                            radius: width / 2
                            color: opened.island.glyphColor(modelData)
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: opened.island.kindsText(row.modelData.kinds)
                        elide: Text.ElideRight
                        color: opened.sub
                        font.family: opened.island.metrics.family
                        font.pixelSize: opened.island.metrics.font(12)
                    }
                }
            }
            IslandButton {
                visible: row.modelData.action !== ""
                text: row.modelData.action === "mute" ? i18nc("@action:button", "Mute")
                    : row.modelData.action === "unmute" ? i18nc("@action:button", "Unmute")
                    : row.modelData.action === "stop" ? i18nc("@action:button", "Stop sharing")
                    : i18nc("@action:button", "End")
                onClicked: opened.island.rowAction(row.modelData)
            }
        }
    }

    // ---- a recording: its time and Stop
    RowLayout {
        visible: opened.item === "recording"
        Layout.fillWidth: true
        Layout.minimumHeight: opened.island.metrics.px(56)
        spacing: opened.island.metrics.px(12)
        Rectangle {
            Layout.preferredWidth: opened.unit
            Layout.preferredHeight: opened.unit
            radius: width / 2
            color: Qt.rgba(217 / 255, 67 / 255, 75 / 255, 0.35)
            Rectangle {
                anchors.centerIn: parent
                width: opened.island.metrics.px(14)
                height: width
                radius: width / 2
                color: opened.island.glyphColor("recording")
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: opened.island.metrics.px(3)
            Text {
                text: i18nc("@info the island, a screen recording", "Recording the screen")
                color: "#ffffff"
                font.family: opened.island.metrics.family
                font.weight: Font.ExtraBold
                font.pixelSize: opened.island.metrics.font(14)
            }
            Text {
                text: i18nc("@info the app that records", "Spectacle")
                color: opened.sub
                font.family: opened.island.metrics.family
                font.pixelSize: opened.island.metrics.font(12)
            }
        }
        Text {
            textFormat: Text.PlainText
            text: opened.island.recording ? opened.island.recording.time : ""
            color: opened.island.glyphColor("recording")
            font.family: opened.island.metrics.displayFamily
            font.weight: Font.DemiBold
            font.pixelSize: opened.island.metrics.font(13)
        }
        IslandButton {
            text: i18nc("@action:button", "Stop")
            ink: "#1b2031"
            fill: opened.island.glyphColor("recording")
            onClicked: opened.island.stopRecording()
        }
    }

    // ---- the music: cover, title, where it is, and its controls
    RowLayout {
        visible: opened.item === "music"
        Layout.fillWidth: true
        spacing: opened.island.metrics.px(12)
        Kirigami.ShadowedImage {
            Layout.preferredWidth: opened.island.metrics.px(52)
            Layout.preferredHeight: opened.island.metrics.px(52)
            visible: opened.media !== null && opened.media.artUrl !== ""
            source: opened.media ? opened.media.artUrl : ""
            radius: opened.island.metrics.px(14)
            fillMode: Image.PreserveAspectCrop
        }
        Kirigami.Icon {
            Layout.preferredWidth: opened.island.metrics.px(52)
            Layout.preferredHeight: opened.island.metrics.px(52)
            visible: opened.media === null || opened.media.artUrl === ""
            source: opened.media && opened.media.iconName !== "" ? opened.media.iconName : "audio-x-generic"
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: opened.island.metrics.px(3)
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: opened.media ? (opened.media.track || opened.media.identity) : ""
                elide: Text.ElideRight
                color: "#ffffff"
                font.family: opened.island.metrics.family
                font.weight: Font.ExtraBold
                font.pixelSize: opened.island.metrics.font(14)
            }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: opened.media ? [opened.media.artist, opened.media.identity].filter(t => t !== "").join(" · ") : ""
                elide: Text.ElideRight
                color: opened.sub
                font.family: opened.island.metrics.family
                font.pixelSize: opened.island.metrics.font(12)
            }
        }
    }
    // Where it is: the position (read again every second while the music is opened) of its length.
    RowLayout {
        visible: opened.item === "music" && opened.media !== null && opened.media.length > 0
        Layout.fillWidth: true
        spacing: opened.island.metrics.px(10)
        Text {
            text: opened.time(opened.media ? opened.media.position : 0)
            color: opened.sub
            font.family: opened.island.metrics.displayFamily
            font.weight: Font.DemiBold
            font.pixelSize: opened.island.metrics.font(11)
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: opened.island.metrics.px(4)
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.2)
            Rectangle {
                width: opened.media && opened.media.length > 0 ? parent.width * Math.min(1, opened.media.position / opened.media.length) : 0
                height: parent.height
                radius: height / 2
                color: "#ffffff"
            }
        }
        Text {
            text: "-" + opened.time(opened.media ? Math.max(0, opened.media.length - opened.media.position) : 0)
            color: opened.sub
            font.family: opened.island.metrics.displayFamily
            font.weight: Font.DemiBold
            font.pixelSize: opened.island.metrics.font(11)
        }
    }
    RowLayout {
        visible: opened.item === "music"
        Layout.alignment: Qt.AlignHCenter
        spacing: opened.island.metrics.px(28)
        Repeater {
            model: [
                { name: i18nc("@action:button music", "Previous"), glyph: "M7 6v12M18 6l-8 6 8 6z", run: "previous", can: "canPrevious" },
                { name: opened.media && opened.media.playing ? i18nc("@action:button music", "Pause") : i18nc("@action:button music", "Play"),
                  glyph: opened.media && opened.media.playing ? "M8 6v12M16 6v12" : "M8 5l11 7-11 7z", run: "playPause", can: "canPlayPause" },
                { name: i18nc("@action:button music", "Next"), glyph: "M17 6v12M6 6l8 6-8 6z", run: "next", can: "canNext" }
            ]
            delegate: Rectangle {
                id: control
                required property var modelData
                required property int index
                Layout.preferredWidth: opened.island.metrics.px(36)
                Layout.preferredHeight: opened.island.metrics.px(36)
                radius: width / 2
                color: index === 1 ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                enabled: opened.media !== null && opened.media[modelData.can]
                opacity: enabled ? 1 : 0.4
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.name
                Accessible.onPressAction: opened.media[modelData.run]()
                Keys.onSpacePressed: opened.media[modelData.run]()
                LineIcon {
                    anchors.centerIn: parent
                    path: control.modelData.glyph
                    color: "#ffffff"
                    size: opened.island.metrics.px(20)
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: opened.media[control.modelData.run]()
                }
            }
        }
    }
    Timer {
        running: opened.item === "music" && opened.media !== null && opened.media.playing
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: opened.media.updatePosition()
    }

    // m:ss of microseconds, as MPRIS gives them.
    function time(us: real): string {
        const s = Math.floor(us / 1000000);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
}
