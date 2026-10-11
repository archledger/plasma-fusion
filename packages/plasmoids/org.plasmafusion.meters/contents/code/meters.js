// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Numbers of the system meters: what each sensor value becomes in the bar and the pop-up, when a
// value counts as high, and how often the meters take a value. No Qt here, so node can test it
// (tests/meters.test.js); the QML formats the numbers with the region's decimal sign.

.pragma library

// A value at or above `high` shows in the warning colour, at or above `critical` in the error
// colour. It goes back only once it is HYSTERESIS below the limit, so a value that hovers at a
// limit does not make the meter flash at every update.
var LIMITS = {
    cpu: { high: 90, critical: Infinity },
    memory: { high: 90, critical: Infinity },
    temperature: { high: 85, critical: 95 }
};
var HYSTERESIS = 5;

// 0 normal, 1 high, 2 critical; `previous` is the level the meter shows now.
function level(kind, value, previous) {
    var limits = LIMITS[kind];
    if (!limits || typeof value !== "number" || !isFinite(value)) {
        return 0;
    }
    var now = value >= limits.critical ? 2 : value >= limits.high ? 1 : 0;
    if (previous === 2 && now < 2 && value > limits.critical - HYSTERESIS) {
        return 2;
    }
    if (previous >= 1 && now < 1 && value > limits.high - HYSTERESIS) {
        return 1;
    }
    return now;
}

// A sensor value that is a real number (libksysguard gives undefined, or an empty string, until
// ksystemstats answered).
function valid(value) {
    return typeof value === "number" && isFinite(value);
}

// Whole percent, 0 to 100; NaN when there is no value.
function percent(value) {
    return valid(value) ? Math.round(Math.max(0, Math.min(100, value))) : NaN;
}

// Used memory as a fraction of the total, 0 to 1; NaN without both values.
function memoryFraction(used, total) {
    if (!valid(used) || !valid(total) || total <= 0) {
        return NaN;
    }
    return Math.max(0, Math.min(1, used / total));
}

// Memory in GiB for "6.1 / 16 GB" (the system card's text): used with one decimal, the total
// rounded up to whole GB from 2 GB on, because the kernel reports a little less than the
// installed modules hold (firmware and graphics reservations: 15.3 GiB for 16 GB).
var GIB = 1024 * 1024 * 1024;
function memory(used, total) {
    if (!valid(used) || !valid(total) || total <= 0) {
        return null;
    }
    var t = total / GIB;
    return {
        used: Math.round(Math.max(0, used) / GIB * 10) / 10,
        total: t >= 2 ? Math.ceil(t - 0.05) : Math.round(t * 10) / 10,
        totalDecimals: t >= 2 ? 0 : 1
    };
}

// A network rate in bytes per second as at most three figures: { value, decimals, unit }, unit
// one of "B", "kB", "MB", "GB", "TB" (decimal units, as link speeds are counted). Under 10 of a
// unit one decimal ("1.2 MB/s"), from 10 whole numbers ("12 MB/s", "999 kB/s"); a value that
// rounds up to 1000 moves to the next unit ("1.0 MB/s"). Bytes are always whole. null without a
// value.
var RATE_UNITS = ["B", "kB", "MB", "GB", "TB"];
function rate(bytesPerSecond) {
    if (!valid(bytesPerSecond)) {
        return null;
    }
    var v = Math.max(0, bytesPerSecond);
    var i = 0;
    if (Math.round(v) < 1000) {
        return { value: Math.round(v), decimals: 0, unit: "B" };
    }
    while (i < RATE_UNITS.length - 1 && v >= 999.5) {
        v /= 1000;
        ++i;
    }
    if (Math.round(v * 10) / 10 < 10) {
        return { value: Math.round(v * 10) / 10, decimals: 1, unit: RATE_UNITS[i] };
    }
    return { value: Math.round(v), decimals: 0, unit: RATE_UNITS[i] };
}

// The samples that bound the width of a rate in the bar (each unit with three whole figures and
// with one decimal), so the meter's box never changes width while the rate changes.
function rateSamples() {
    var samples = [];
    for (var i = 0; i < RATE_UNITS.length; ++i) {
        samples.push({ value: 888, decimals: 0, unit: RATE_UNITS[i] });
        samples.push({ value: 8.8, decimals: 1, unit: RATE_UNITS[i] });
    }
    return samples;
}

// A CPU temperature reading in °C: ksystemstats reports 0 where the machine has no CPU sensor
// (virtual machines, some ARM boards), so only 1 to 199 °C count.
function temperatureValid(celsius) {
    return valid(celsius) && celsius >= 1 && celsius < 200;
}

// Whole degrees in the region's unit (Fahrenheit for regions that use it); NaN without a reading.
function temperature(celsius, fahrenheit) {
    if (!temperatureValid(celsius)) {
        return NaN;
    }
    return Math.round(fahrenheit ? celsius * 9 / 5 + 32 : celsius);
}

// Milliseconds between two values: the user's interval (1 to 10 s) times the power tier's factor
// (x 1 full, x 2 power saver, x 4 critical battery), as the system card counts it.
function interval(updateInterval, powerTier) {
    var ms = valid(updateInterval) ? Math.max(1000, Math.min(10000, updateInterval)) : 2000;
    var tier = valid(powerTier) ? Math.max(0, Math.min(2, Math.round(powerTier))) : 0;
    return ms * (1 << tier);
}

// The meters to show, in the bar's order, from the four settings.
function shown(cpu, memory, network, temperature) {
    var list = [];
    if (cpu) {
        list.push("cpu");
    }
    if (memory) {
        list.push("memory");
    }
    if (network) {
        list.push("network");
    }
    if (temperature) {
        list.push("temperature");
    }
    return list;
}
