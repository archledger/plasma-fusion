// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/weather.js (not installed). Run: node tests/weather.test.js
// Replies are the ones the Plasma 6.7.5 weather engine gave on 2026-09-29.
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

// weather.js runs as a script of its own named by its file URL, so V8's coverage (node --test
// --experimental-test-coverage, tools/tests/coverage.sh) maps it to the file. The QML-only
// ".pragma library" line becomes spaces of the same length, which keeps every offset; the
// library's top-level names become globals of this test.
const file = path.join(__dirname, "..", "contents", "code", "weather.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const W = Object.fromEntries(["isSafeSource", "weatherSource", "searchText", "parseValidate", "parseIons",
                              "hasWeather", "displayUnit", "degrees", "forecastDay", "highLow", "sentenceCase",
                              "glyphFor", "shortPlace", "regionalIon", "Celsius", "Fahrenheit", "Kelvin"]
                             .map((name) => [name, globalThis[name]]));
for (const [name, value] of Object.entries(W))
    assert.notStrictEqual(value, undefined, `weather.js does not define ${name}`);

// Sources the ions would crash on or misread are never accepted.
assert.strictEqual(W.isSafeSource("bbcukmet|weather|London, Greater London, GB|2643743"), true);
assert.strictEqual(W.isSafeSource("bbcukmet|weather|place"), false);          // no station: crashes the ion
assert.strictEqual(W.isSafeSource("bbcukmet|weather|London"), false);
assert.strictEqual(W.isSafeSource("noaa|weather|Boston, Logan International Airport, MA"), true);
assert.strictEqual(W.isSafeSource("envcan|weather|Toronto, ON"), true);
assert.strictEqual(W.isSafeSource("wettercom|weather|Berlin, Berlin, DE|DE0001020;Berlin"), true);
assert.strictEqual(W.isSafeSource("wettercom|weather|Berlin, Berlin, DE|DE0001020"), false);
assert.strictEqual(W.isSafeSource("dwd|weather|BERLIN-TEMPELHOF|10384"), true);
assert.strictEqual(W.isSafeSource("dwd|weather|BERLIN-TEMPELHOF"), false);
assert.strictEqual(W.isSafeSource("noaa|validate|Boston"), false);
assert.strictEqual(W.isSafeSource("noaa|weather|"), false);
assert.strictEqual(W.isSafeSource("noaa|weather| |x|y"), false);
assert.strictEqual(W.isSafeSource(""), false);
assert.strictEqual(W.isSafeSource(undefined), false);

assert.strictEqual(W.searchText("  New | York  "), "New York");

// The region's own provider is listed first among equal matches.
assert.strictEqual(W.regionalIon("en_GB"), "bbcukmet");
assert.strictEqual(W.regionalIon("en_US"), "noaa");
assert.strictEqual(W.regionalIon("fr_CA"), "envcan");
assert.strictEqual(W.regionalIon("de_DE"), "dwd");
assert.strictEqual(W.regionalIon("de_AT"), "");
assert.strictEqual(W.regionalIon("C"), "");
assert.strictEqual(W.regionalIon(undefined), "");

const bbc = "bbcukmet|valid|multiple||place|London, Canada, CA|extra|6058560|place|London, Greater London, GB|extra|2643743";
assert.deepStrictEqual(W.parseValidate(bbc).map(e => e.source), [
    "bbcukmet|weather|London, Canada, CA|6058560",
    "bbcukmet|weather|London, Greater London, GB|2643743"]);
assert.deepStrictEqual(W.parseValidate("noaa|valid|single|place|Boston, Logan International Airport, MA").map(e => e.source),
                       ["noaa|weather|Boston, Logan International Airport, MA"]);
assert.deepStrictEqual(W.parseValidate("envcan|valid|multiple|place|Toronto Island, ON|place|Toronto, ON").map(e => e.place),
                       ["Toronto Island, ON", "Toronto, ON"]);
assert.deepStrictEqual(W.parseValidate("noaa|invalid|single|Nowhere"), []);
assert.deepStrictEqual(W.parseValidate("bbcukmet|malformed"), []);
// An ion that needs a station but gave none: dropped rather than connected.
assert.deepStrictEqual(W.parseValidate("bbcukmet|valid|single|place|London"), []);

assert.deepStrictEqual(W.parseIons({ "plasma_engine_noaa": "NOAA's National Weather Service|noaa",
                                     "plasma_engine_bbcukmet": "BBC Weather|bbcukmet" }),
                       [{ ion: "bbcukmet", name: "BBC Weather" }, { ion: "noaa", name: "NOAA's National Weather Service" }]);

assert.strictEqual(W.displayUnit(0, true), W.Celsius);
assert.strictEqual(W.displayUnit(0, false), W.Fahrenheit);
assert.strictEqual(W.displayUnit(2, true), W.Fahrenheit);
assert.strictEqual(W.degrees(66.2, W.Fahrenheit, W.Celsius), "19°");
assert.strictEqual(W.degrees(21, W.Celsius, W.Celsius), "21°");
assert.strictEqual(W.degrees(21, W.Celsius, W.Fahrenheit), "70°");
assert.strictEqual(W.degrees(-0.4, W.Celsius, W.Celsius), "0°");
assert.strictEqual(W.degrees(-2.5, W.Celsius, W.Celsius), "-3°");
assert.strictEqual(W.degrees(290.15, W.Kelvin, W.Celsius), "17°");
assert.strictEqual(W.degrees("N/A", W.Celsius, W.Celsius), "");
assert.strictEqual(W.degrees(undefined, W.Celsius, W.Celsius), "");

// NOAA: day and night of the same date; BBC at night: tonight's low only.
const noaa = { "Short Forecast Day 0": "29|weather-overcast|Mostly Cloudy|66|N/A|3",
               "Short Forecast Day 1": "29|weather-overcast|Mostly Cloudy|N/A|57|4" };
assert.deepStrictEqual(W.highLow(noaa), { high: 66, low: 57 });
const bbcNight = { "Short Forecast Day 0": "Tonight|weather-storm|thundery showers||18|46",
                   "Short Forecast Day 1": "Wed|weather-showers-scattered|light rain|23|14|57" };
const hl = W.highLow(bbcNight);
assert.ok(isNaN(hl.high) && hl.low === 18);
assert.deepStrictEqual(W.highLow({}), { high: NaN, low: NaN });

assert.strictEqual(W.sentenceCase("Partly Cloudy", true), "Partly cloudy");
assert.strictEqual(W.sentenceCase("light rain", true), "Light rain");
assert.strictEqual(W.sentenceCase("Leichter Regen", false), "Leichter Regen");

assert.strictEqual(W.glyphFor("weather-clouds"), "cloud");
assert.strictEqual(W.glyphFor("weather-few-clouds"), "sunCloud");
assert.strictEqual(W.glyphFor("weather-few-clouds-night"), "moonCloud");
assert.strictEqual(W.glyphFor("weather-clear-night"), "moon");
assert.strictEqual(W.glyphFor("weather-clear"), "sun");
assert.strictEqual(W.glyphFor("weather-showers-scattered-day"), "rain");
assert.strictEqual(W.glyphFor("weather-snow-rain"), "snow");
assert.strictEqual(W.glyphFor("weather-storm-night"), "storm");
assert.strictEqual(W.glyphFor("weather-fog"), "fog");
assert.strictEqual(W.glyphFor("weather-overcast"), "cloud");
assert.strictEqual(W.glyphFor("weather-none-available"), "");

assert.strictEqual(W.shortPlace("London, Greater London, GB"), "London");

assert.strictEqual(W.hasWeather({}), false);
assert.strictEqual(W.hasWeather(null), false);
assert.strictEqual(W.hasWeather({ validate: "bbcukmet|malformed" }), false);
assert.strictEqual(W.hasWeather(bbcNight), true);
assert.strictEqual(W.hasWeather({ Temperature: 0 }), true);

console.log("weather.js: all tests passed");
