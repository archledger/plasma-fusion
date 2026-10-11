/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ksysguard.sensors as Sensors

import "../code/meters.js" as Meters

// The sensor values of the system meters, from ksystemstats through org.kde.ksysguard.sensors as
// the system card and the stock System Monitor widgets read them. A sensor is subscribed only
// while its meter is shown (or the pop-up is open) and the meters can be seen: libksysguard
// unsubscribes a disabled sensor, and ksystemstats stops reading what nobody subscribes. Nothing
// here polls: ksystemstats sends each value when it reads it (every 500 ms) and the rate limit
// keeps one per interval.
Item {
    id: readings

    // The meters can be seen (shown, not covered, the session not locked).
    property bool active: false
    // The meters turned on in the settings.
    property bool cpuWanted: false
    property bool memoryWanted: false
    property bool networkWanted: false
    property bool temperatureWanted: false
    // The pop-up is open: every value it shows.
    property bool details: false
    // Milliseconds between two values (0: every tick, after a pause).
    property int rateLimit: 2000

    readonly property bool cpuOn: active && (cpuWanted || details)
    readonly property bool memoryOn: active && (memoryWanted || details)
    readonly property bool networkOn: active && (networkWanted || details)
    readonly property bool temperatureOn: active && (temperatureWanted || details)

    // The sensors subscribed now (tests and the debug dump).
    readonly property var subscribed: {
        const ids = [];
        for (const s of [cpuSensor, coresSensor, memUsedSensor, memTotalSensor, downSensor, upSensor, tempSensor]) {
            if (s.enabled) {
                ids.push(s.sensorId);
            }
        }
        return ids;
    }

    readonly property real cpu: Meters.valid(cpuSensor.value) ? cpuSensor.value : NaN
    readonly property real cores: Meters.valid(coresSensor.value) ? coresSensor.value : NaN
    readonly property real memoryUsed: Meters.valid(memUsedSensor.value) ? memUsedSensor.value : NaN
    readonly property real memoryTotal: Meters.valid(memTotalSensor.value) ? memTotalSensor.value : NaN
    readonly property real download: Meters.valid(downSensor.value) ? downSensor.value : NaN
    readonly property real upload: Meters.valid(upSensor.value) ? upSensor.value : NaN
    readonly property real temperature: Meters.temperatureValid(tempSensor.value) ? tempSensor.value : NaN

    signal valueArrived(string sensorId)

    Sensors.Sensor {
        id: cpuSensor
        sensorId: "cpu/all/usage"
        enabled: readings.cpuOn
        updateRateLimit: readings.rateLimit
        onValueChanged: readings.valueArrived(sensorId)
    }
    // Shown in the pop-up only; it never changes, so it is read while the pop-up is open.
    Sensors.Sensor {
        id: coresSensor
        sensorId: "cpu/all/coreCount"
        enabled: readings.active && readings.details
    }
    Sensors.Sensor {
        id: memUsedSensor
        sensorId: "memory/physical/used"
        enabled: readings.memoryOn
        updateRateLimit: readings.rateLimit
        onValueChanged: readings.valueArrived(sensorId)
    }
    Sensors.Sensor {
        id: memTotalSensor
        sensorId: "memory/physical/total"
        enabled: readings.memoryOn
        updateRateLimit: readings.rateLimit
    }
    Sensors.Sensor {
        id: downSensor
        sensorId: "network/all/download"
        enabled: readings.networkOn
        updateRateLimit: readings.rateLimit
        onValueChanged: readings.valueArrived(sensorId)
    }
    Sensors.Sensor {
        id: upSensor
        sensorId: "network/all/upload"
        enabled: readings.networkOn
        updateRateLimit: readings.rateLimit
        onValueChanged: readings.valueArrived(sensorId)
    }
    // The hottest core: the value that matters when the machine runs hot.
    Sensors.Sensor {
        id: tempSensor
        sensorId: "cpu/all/maximumTemperature"
        enabled: readings.temperatureOn
        updateRateLimit: readings.rateLimit
        onValueChanged: readings.valueArrived(sensorId)
    }
}
