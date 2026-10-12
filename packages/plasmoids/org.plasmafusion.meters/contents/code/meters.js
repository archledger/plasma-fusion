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

// The windows that cover the top bar, of `windows` ({fullScreen, active}: this screen's windows on
// the current desktop and activity). KWin draws a full-screen window above the panels only while
// it is the active window or while the active window is on another screen; otherwise it sits in
// the normal layer, under the bar (kwin 6.7, Window::belongsToLayer() and isActiveFullScreen()).
// `activeAnywhere`: a window of the session is active. When none is (a panel, a pop-up or the
// desktop has the focus) no full-screen window is above the bar.
function coveringWindows(windows, activeAnywhere) {
    var activeHere = false;
    for (var i = 0; i < windows.length; ++i) {
        activeHere = activeHere || windows[i].active === true;
    }
    var n = 0;
    for (var j = 0; j < windows.length; ++j) {
        var w = windows[j];
        if (w.fullScreen === true && (w.active === true || (activeAnywhere && !activeHere))) {
            ++n;
        }
    }
    return n;
}

// Whether a bar is on a screen that is there: `screen` is its containment's screen index (-1 when
// it has none), `screens` how many screens there are. Plasma 6.7 gives a bar left over from a
// screen that is gone -1; Plasma 6.8 keeps the screen it was on (an index past the last screen),
// and its window can stay visible although nothing shows it. Without a containment the widget is
// taken as on a screen (a stand-alone test window).
function barOnScreen(hasContainment, screen, screens) {
    if (!hasContainment) {
        return true;
    }
    return screen >= 0 && screen < screens;
}

// Whether the pop-up opens on a request (a click, Enter, the widget's shortcut): only under the
// pill while it is shown in a window on a screen. Asked while the width budget or tablet posture
// took the meters out of the bar, or the bar has no screen, nothing could show the pop-up, and an
// "open" state would keep every sensor subscribed until the shortcut is pressed again.
function popupOpens(wanted, pillShown, onScreen) {
    return wanted === true && pillShown === true && onScreen === true;
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
