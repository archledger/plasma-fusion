/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick

import org.kde.plasma.private.volume as PlasmaPa

import "../code/audio.js" as AudioMatch

// The apps' audio streams (plasma-pa sink inputs) for the dock's audio indicator and mute,
// matched to a task as the stock task manager's PulseAudio.qml does (code/audio.js). The stock
// task manager also tries the stream's parent process; its helper for that is private to the
// stock applet, so a stream from an app's helper process falls back to the name.
// main.qml loads this file through a Loader: without plasma-pa the dock has no indicator.
QtObject {
    id: audio

    // Streams came or went (or an app's process id was first matched): read them again.
    signal streamsChanged()

    // Apps whose streams were matched by process id.
    property var pidMatches: new Set()

    function find(test: var): var {
        const out = [];
        for (let i = 0; i < instantiator.count; ++i) {
            const stream = instantiator.objectAt(i);
            if (stream && test(stream)) {
                out.push(stream);
            }
        }
        return out;
    }

    function streamsFor(appId: string, pid: int, appName: string): var {
        const r = AudioMatch.match(find(() => true), name => pidMatches.has(name), appId, pid, appName);
        if (r.pidMatch !== "" && !pidMatches.has(r.pidMatch)) {
            pidMatches.add(r.pidMatch);
            Qt.callLater(audio.streamsChanged);
        }
        return r.streams;
    }

    readonly property Instantiator instantiator: Instantiator {
        model: PlasmaPa.PulseObjectFilterModel {
            filters: [{ role: "VirtualStream", value: false }]
            sourceModel: PlasmaPa.SinkInputModel {}
        }
        delegate: QtObject {
            required property var model
            readonly property int pid: Number(model.Client?.properties["application.process.id"] ?? 0)
            readonly property string appName: model.Client?.properties["application.name"] ?? ""
            readonly property string portalAppId: model.Client?.properties["pipewire.access.portal.app_id"] ?? ""
            readonly property bool muted: model.Muted
            // Nothing is playing on the stream (paused).
            readonly property bool corked: model.Corked
            function setMuted(on: bool): void {
                model.Muted = on;
            }
        }
        onObjectAdded: Qt.callLater(audio.streamsChanged)
        onObjectRemoved: Qt.callLater(audio.streamsChanged)
    }
}
