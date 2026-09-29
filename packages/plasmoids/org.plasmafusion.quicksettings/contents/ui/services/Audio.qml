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
}
