// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import "components"
import "components/Icons.js" as Icons

ColumnLayout {
    id: streams
    required property var backend
    required property FusionPalette pal
    required property FusionMetrics metrics
    spacing: metrics.px(12)

    component Group: ColumnLayout {
        id: group
        required property var streamModel
        required property var devices
        required property string title
        spacing: streams.metrics.px(8)
        FText {
            Layout.fillWidth: true
            pal: streams.pal
            metrics: streams.metrics
            text: group.title
            font.weight: Font.ExtraBold
        }
        FText {
            Layout.fillWidth: true
            visible: list.count === 0
            pal: streams.pal
            metrics: streams.metrics
            color: streams.pal.secondary
            text: i18nc("@info", "No active applications")
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: contentHeight
            interactive: false
            spacing: streams.metrics.px(10)
            model: group.streamModel
            delegate: ColumnLayout {
                id: row
                required property var model
                readonly property var stream: model.PulseObject
                width: ListView.view.width
                spacing: streams.metrics.px(5)
                FText {
                    Layout.fillWidth: true
                    pal: streams.pal
                    metrics: streams.metrics
                    text: (row.model.Client && row.model.Client.name) || row.model.Name || i18nc("@info", "Application")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.fillWidth: true
                    IconButton {
                        pal: streams.pal
                        size: streams.pal.touch ? 44 : 28
                        iconPath: row.stream && row.stream.muted ? Icons.speaker + Icons.muteCross : Icons.speaker + Icons.wave1
                        text: row.stream && row.stream.muted ? i18nc("@action:button", "Unmute application")
                                                             : i18nc("@action:button", "Mute application")
                        onClicked: streams.backend.audio.toggleStreamMute(row.stream)
                    }
                    FusionSlider {
                        Layout.fillWidth: true
                        pal: streams.pal
                        enabled: !!row.stream && row.stream.hasVolume
                        dimmed: !!row.stream && row.stream.muted
                        value: row.stream ? row.stream.volume / streams.backend.audio.normal : 0
                        Accessible.name: i18nc("@label:slider", "Application volume")
                        onMoved: streams.backend.audio.setStreamVolume(row.stream, value)
                        onDraggingChanged: if (!dragging) {
                            value = Qt.binding(() => row.stream ? row.stream.volume / streams.backend.audio.normal : 0);
                        }
                    }
                }
                QQC2.ComboBox {
                    Layout.fillWidth: true
                    model: group.devices
                    textRole: "Description"
                    valueRole: "Index"
                    currentIndex: row.stream ? indexOfValue(row.stream.deviceIndex) : -1
                    Accessible.name: i18nc("@label:listbox", "Application audio device")
                    onActivated: streams.backend.audio.routeStream(row.stream, currentValue)
                }
            }
        }
    }
    Group {
        Layout.fillWidth: true
        title: i18nc("@title:group", "Playback")
        streamModel: streams.backend.audio.playbackModel
        devices: streams.backend.audio.sinkModel
    }
    Group {
        Layout.fillWidth: true
        title: i18nc("@title:group", "Recording")
        streamModel: streams.backend.audio.recordingModel
        devices: streams.backend.audio.sourceModel
    }
}
