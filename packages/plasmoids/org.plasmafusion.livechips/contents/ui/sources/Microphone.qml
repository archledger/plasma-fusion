// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.private.volume

// The apps recording from a microphone, by plasma-pa's own rule (its MicrophoneIndicator): every
// source output that is not a virtual stream, while a microphone exists. main.qml loads this file
// with a Loader, so a system without plasma-pa's QML module has no microphone chip.
Item {
    id: microphone

    // One entry per recording stream: { name, muted, setMuted(bool) } (the stream's own mute: the
    // app stops hearing the microphone, other apps do not).
    property var apps: []
    readonly property bool inUse: apps.length > 0

    function refresh(): void {
        const list = [];
        if (sources.rowCount() > 0) {
            for (let i = 0; i < rows.count; ++i) {
                const row = rows.objectAt(i);
                if (row && !row.virtualStream) {
                    list.push(row);
                }
            }
        }
        apps = list;
    }

    SourceModel {
        id: sources
    }
    Connections {
        target: sources
        function onRowsInserted() { Qt.callLater(microphone.refresh); }
        function onRowsRemoved() { Qt.callLater(microphone.refresh); }
        function onModelReset() { Qt.callLater(microphone.refresh); }
    }

    Instantiator {
        id: rows
        model: SourceOutputModel {}
        delegate: QtObject {
            required property var model
            readonly property bool virtualStream: model.VirtualStream === true
            // The app's name as plasma-pa's own list shows it.
            readonly property string name: {
                const client = model.Client;
                if (client && client.name && client.name !== "pipewire-media-session") {
                    return String(client.name);
                }
                return String(model.Name || "");
            }
            readonly property bool muted: model.Muted === true
            function setMuted(value: bool): void {
                model.Muted = value;
            }
            onVirtualStreamChanged: Qt.callLater(microphone.refresh)
            onNameChanged: Qt.callLater(microphone.refresh)
            onMutedChanged: Qt.callLater(microphone.refresh)
        }
        onObjectAdded: Qt.callLater(microphone.refresh)
        onObjectRemoved: Qt.callLater(microphone.refresh)
    }
}
