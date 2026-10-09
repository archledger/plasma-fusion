// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.private.volume

// Output volume through plasma-pa (PulseAudio / PipeWire-Pulse).
Item {
    id: audio

    readonly property var sink: PreferredDevice.sink
    readonly property bool available: !!sink && sink.name !== "auto_null"
    readonly property real normal: PulseAudio.NormalVolume
    // 0..1 for 0..100 %, may exceed 1 when the volume was raised above 100 %.
    readonly property real volume: available ? sink.volume / normal : 0
    readonly property bool muted: available ? sink.muted : true
    readonly property string deviceName: available ? (sink.description || sink.name || "") : ""
    readonly property var sinkModel: sinks
    readonly property int sinkCount: sinks.count
    readonly property var source: PreferredDevice.source
    readonly property bool inputAvailable: !!source && source.name !== "auto_null.monitor"
    readonly property string inputName: inputAvailable ? source.name : ""
    readonly property string inputDescription: inputAvailable ? (source.description || source.name) : ""
    readonly property real inputVolume: inputAvailable ? source.volume / normal : 0
    readonly property bool inputMuted: inputAvailable ? source.muted : true
    readonly property var sourceModel: sources
    readonly property var playbackModel: playback
    readonly property var recordingModel: recording

    function setInputVolume(fraction: real): void {
        if (inputAvailable) {
            const v = Math.max(0, Math.min(1, fraction));
            source.volume = Math.round(v * normal);
            source.muted = v === 0;
        }
    }
    function toggleInputMute(): void {
        if (inputAvailable) {
            source.muted = !source.muted;
        }
    }
    function setStreamVolume(stream: var, fraction: real): void {
        if (stream && stream.hasVolume) {
            const v = Math.max(0, Math.min(1, fraction));
            stream.volume = Math.round(v * normal);
            stream.muted = v === 0;
        }
    }
    function toggleStreamMute(stream: var): void {
        if (stream) {
            stream.muted = !stream.muted;
        }
    }
    function routeStream(stream: var, deviceIndex: int): void {
        if (stream && deviceIndex >= 0) {
            stream.deviceIndex = deviceIndex;
        }
    }

    function setVolume(fraction: real) {
        if (!available) {
            return;
        }
        const v = Math.max(0, Math.min(1, fraction));
        sink.volume = Math.round(v * normal);
        sink.muted = v === 0;
    }
    function toggleMute() {
        if (available) {
            sink.muted = !sink.muted;
        }
    }
    function setDefault(pulseObject) {
        if (pulseObject) {
            pulseObject.default = true;
        }
    }

    PulseObjectFilterModel {
        id: sinks
        filterOutInactiveDevices: true
        filterVirtualDevices: true
        sourceModel: SinkModel {}
    }
    PulseObjectFilterModel {
        id: sources
        filterOutInactiveDevices: true
        // Virtual microphones (noise suppression/remapped inputs) remain useful inputs. The outputs'
        // monitors never reach SourceModel: pulseaudio-qt leaves out every monitor source.
        sourceModel: SourceModel {}
    }
    // Application streams only: virtual streams (modules' loopbacks, monitors, event sounds) are not
    // applications to mute or route; the dock filters its streams the same way.
    PulseObjectFilterModel {
        id: playback
        filters: [{ role: "VirtualStream", value: false }]
        sourceModel: SinkInputModel {}
    }
    PulseObjectFilterModel {
        id: recording
        filters: [{ role: "VirtualStream", value: false }]
        sourceModel: SourceOutputModel {}
    }
}
