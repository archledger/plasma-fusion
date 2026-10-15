// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtMultimedia
import org.kde.kirigami as Kirigami

// A video or a song, playing at once (Qt Multimedia): the video, or the song's cover (its KIO
// thumbnail) or icon, with play/pause and the position below.
Item {
    id: viewer
    objectName: "mediaViewer"

    // QuickLookItem (quicklook.h).
    required property var item
    readonly property bool failed: player.error !== MediaPlayer.NoError || player.mediaStatus === MediaPlayer.InvalidMedia
    readonly property bool ready: failed || player.duration > 0
    readonly property var report: ({
        status: failed ? "error" : "ready",
        duration: player.duration,
        hasVideo: player.hasVideo,
        hasAudio: player.hasAudio,
        error: player.errorString
    })
    readonly property string extra: player.duration > 0 ? timeText(player.duration) : ""

    function timeText(ms) {
        const seconds = Math.floor(ms / 1000);
        const minutes = Math.floor(seconds / 60);
        const hours = Math.floor(minutes / 60);
        const two = n => (n < 10 ? "0" : "") + n;
        return hours > 0 ? hours + ":" + two(minutes % 60) + ":" + two(seconds % 60) : minutes + ":" + two(seconds % 60);
    }

    MediaPlayer {
        id: player
        source: viewer.item.url
        audioOutput: AudioOutput {}
        videoOutput: video
        Component.onCompleted: play()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            VideoOutput {
                id: video
                anchors.fill: parent
                visible: player.hasVideo
            }
            // A song: its cover, else the file's icon.
            Image {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) * 0.6
                height: width
                visible: !player.hasVideo && status === Image.Ready
                source: viewer.item.thumbnail
                fillMode: Image.PreserveAspectFit
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.enormous
                height: width
                visible: !player.hasVideo && viewer.item.thumbnail.toString().length === 0
                source: viewer.item.iconName
            }
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: viewer.failed
                icon.name: "dialog-warning"
                text: i18nc("@info", "This file cannot be played here")
                explanation: player.errorString
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            enabled: !viewer.failed

            QQC2.ToolButton {
                icon.name: player.playbackState === MediaPlayer.PlayingState ? "media-playback-pause" : "media-playback-start"
                text: player.playbackState === MediaPlayer.PlayingState ? i18nc("@action:button", "Pause") : i18nc("@action:button", "Play")
                display: QQC2.AbstractButton.IconOnly
                onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
            }
            QQC2.Slider {
                Layout.fillWidth: true
                from: 0
                to: Math.max(1, player.duration)
                value: player.position
                enabled: player.seekable
                Accessible.name: i18nc("@label the playing position", "Position")
                onMoved: player.position = value
            }
            QQC2.Label {
                text: viewer.timeText(player.position) + " / " + viewer.timeText(player.duration)
                font.features: {"tnum": 1}
            }
        }
    }
}
