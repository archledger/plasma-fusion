.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Helpers for the Plasma5Support "weather" data engine (plasma5support 6.7.5,
    src/dataengines/weather). Source names:
        ions                                 plugin id -> "Display name|ion"
        <ion>|validate|<search text>         "validate" -> "<ion>|valid|single|place|<name>[|extra|<id>]..."
        <ion>|weather|<place>[|<extra>]      observation and forecast of one place
    The ions parse these names by splitting on '|' and index fields without bounds checks
    (bbcukmet reads field 3 of a weather source unconditionally), so every weather source is
    built only from a validate reply and checked with isSafeSource() before it is connected.
*/

// Ions that need the "extra" field (station or place code) in a weather source.
var ionsNeedingExtra = ["bbcukmet", "dwd", "wettercom"];

// KUnitConversion ids used by the engine for "Temperature Unit".
var Kelvin = 6000;
var Celsius = 6001;
var Fahrenheit = 6002;

function isSafeSource(source) {
    if (typeof source !== "string" || source.length === 0 || source.length > 512) {
        return false;
    }
    const f = source.split("|");
    if (f.length < 3 || f.length > 4) {
        return false;
    }
    if (!/^[a-z0-9_.-]+$/.test(f[0]) || f[1] !== "weather" || f[2].trim().length === 0) {
        return false;
    }
    if (f.length === 4 && f[3].length === 0) {
        return false;
    }
    if (ionsNeedingExtra.indexOf(f[0]) !== -1 && f.length !== 4) {
        return false;
    }
    if (f[0] === "wettercom" && f[3].split(";").length !== 2) {
        return false;
    }
    return true;
}

// Weather source for one validate result, or "" when it would not be safe.
function weatherSource(ion, place, extra) {
    const clean = s => String(s || "").replace(/\|/g, " ").trim();
    const src = clean(ion) + "|weather|" + clean(place) + (extra ? "|" + clean(extra) : "");
    return isSafeSource(src) ? src : "";
}

// Search text that can go into a validate source (no field separator, trimmed).
function searchText(text) {
    return String(text || "").replace(/\|/g, " ").replace(/\s+/g, " ").trim();
}

// Parses a "validate" reply into [{ion, place, extra, source}] (unsafe entries dropped).
function parseValidate(reply) {
    const out = [];
    if (typeof reply !== "string") {
        return out;
    }
    const f = reply.split("|");
    if (f.length < 4 || f[1] !== "valid") {
        return out;
    }
    const ion = f[0];
    for (let i = 3; i < f.length; ++i) {
        if (f[i] !== "place" || i + 1 >= f.length || f[i + 1] === "") {
            continue;
        }
        const entry = { ion: ion, place: f[i + 1], extra: "" };
        i += 1;
        if (f[i + 1] === "extra" && i + 2 < f.length) {
            entry.extra = f[i + 2];
            i += 2;
        }
        entry.source = weatherSource(ion, entry.place, entry.extra);
        if (entry.source !== "") {
            out.push(entry);
        }
    }
    return out;
}

// "ions" source data -> [{ion, name}], sorted by name.
function parseIons(data) {
    const out = [];
    if (!data) {
        return out;
    }
    for (const key in data) {
        const parts = String(data[key]).split("|");
        if (parts.length >= 2 && /^[a-z0-9_.-]+$/.test(parts[1])) {
            out.push({ ion: parts[1], name: parts[0] });
        }
    }
    out.sort((a, b) => a.name.localeCompare(b.name));
    return out;
}

// True when a weather source reply holds an observation or a forecast (the engine first
// answers with an empty map, and a failed request only with a "validate" error).
function hasWeather(data) {
    return !!data && (data["Temperature"] !== undefined || data["Short Forecast Day 0"] !== undefined);
}

// Display unit: 0 = from the region (metric: true in every region but those with US units),
// 1 = Celsius, 2 = Fahrenheit.
function displayUnit(setting, metric) {
    if (setting === 1) {
        return Celsius;
    }
    if (setting === 2) {
        return Fahrenheit;
    }
    return metric ? Celsius : Fahrenheit;
}

function toNumber(value) {
    if (value === undefined || value === null || value === "" || value === "N/A") {
        return NaN;
    }
    const n = Number(value);
    return isFinite(n) ? n : NaN;
}

function convert(value, fromUnit, toUnit) {
    let v = toNumber(value);
    if (isNaN(v)) {
        return NaN;
    }
    // to Celsius
    if (fromUnit === Fahrenheit) {
        v = (v - 32) * 5 / 9;
    } else if (fromUnit === Kelvin) {
        v = v - 273.15;
    } else if (fromUnit !== Celsius) {
        return NaN;
    }
    return toUnit === Fahrenheit ? v * 9 / 5 + 32 : v;
}

// "18°", or "" when the value is missing. Rounds half away from zero ("-0" never shown).
function degrees(value, fromUnit, toUnit) {
    const v = convert(value, fromUnit, toUnit);
    if (isNaN(v)) {
        return "";
    }
    let r = Math.round(Math.abs(v)) * Math.sign(v);
    if (r === 0) {
        r = 0;
    }
    return r + "°";
}

// Fields of "Short Forecast Day N": period|icon|summary|high|low|probability.
function forecastDay(data, n) {
    const raw = data ? data["Short Forecast Day " + n] : undefined;
    if (typeof raw !== "string") {
        return null;
    }
    const f = raw.split("|");
    return { period: f[0] || "", icon: f[1] || "", summary: f[2] || "", high: toNumber(f[3]), low: toNumber(f[4]) };
}

// Today's high and low: the first forecast entry, completed by the second when both describe the
// same period (NOAA splits a day into a day and a night entry with the same date).
function highLow(data) {
    const d0 = forecastDay(data, 0);
    if (!d0) {
        return { high: NaN, low: NaN };
    }
    let high = d0.high;
    let low = d0.low;
    const d1 = forecastDay(data, 1);
    if (d1 && d1.period === d0.period) {
        if (isNaN(high)) {
            high = d1.high;
        }
        if (isNaN(low)) {
            low = d1.low;
        }
    }
    return { high: high, low: low };
}

// Condition text in sentence case ("Partly Cloudy" -> "Partly cloudy" for English).
function sentenceCase(text, english) {
    const t = String(text || "").trim();
    if (t === "") {
        return "";
    }
    const rest = english ? t.slice(1).toLowerCase() : t.slice(1);
    return t.charAt(0).toUpperCase() + rest;
}

// Freedesktop weather icon name (as the ions report it, plasma5support ion.cpp getWeatherIcon)
// -> glyph of the card: sun, moon, sunCloud, moonCloud, cloud, rain, snow, storm, fog.
// "weather-clouds" is the ions' "partly cloudy": the board draws that as the plain cloud.
function glyphFor(iconName) {
    const n = String(iconName || "");
    if (n === "" || n.indexOf("none-available") !== -1) {
        return "";
    }
    if (n.indexOf("storm") !== -1) {
        return "storm";
    }
    if (n.indexOf("snow") !== -1 || n.indexOf("hail") !== -1 || n.indexOf("freezing") !== -1) {
        return "snow";
    }
    if (n.indexOf("shower") !== -1 || n.indexOf("rain") !== -1) {
        return "rain";
    }
    if (n.indexOf("fog") !== -1 || n.indexOf("mist") !== -1 || n.indexOf("haze") !== -1) {
        return "fog";
    }
    if (n.indexOf("few-clouds") !== -1) {
        return n.indexOf("night") !== -1 ? "moonCloud" : "sunCloud";
    }
    if (n.indexOf("clouds") !== -1 || n.indexOf("overcast") !== -1) {
        return "cloud";
    }
    if (n.indexOf("clear") !== -1) {
        return n.indexOf("night") !== -1 ? "moon" : "sun";
    }
    return "cloud";
}

// Provider of the region's own weather service ("en_GB" -> bbcukmet, "en_US" -> noaa), or "".
// Its places are listed first among equally good matches of a search.
var regionalIons = { "US": "noaa", "GB": "bbcukmet", "CA": "envcan", "DE": "dwd" };
function regionalIon(localeName) {
    const m = /^[a-z]{2,3}[_-]([A-Z]{2})/.exec(String(localeName || ""));
    return m && regionalIons[m[1]] ? regionalIons[m[1]] : "";
}

// Short place name for the title: "London, Greater London, GB" -> "London".
function shortPlace(place) {
    const p = String(place || "").split(",")[0].trim();
    return p;
}
