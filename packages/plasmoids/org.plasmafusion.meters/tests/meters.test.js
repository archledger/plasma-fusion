// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/meters.js (not installed): formats, limits and the update interval of
// the system meters. Run: node tests/meters.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "meters.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const M = globalThis;

let n = 0;
function test(name, f) {
    f();
    n++;
    console.log("ok " + n + " " + name);
}

test("percent: whole, clamped, NaN without a value", () => {
    assert.strictEqual(M.percent(23.4), 23);
    assert.strictEqual(M.percent(23.5), 24);
    assert.strictEqual(M.percent(-3), 0);
    assert.strictEqual(M.percent(100.7), 100);
    assert(Number.isNaN(M.percent(undefined)), "undefined");
    assert(Number.isNaN(M.percent("")), "an empty value (before ksystemstats answered)");
    assert(Number.isNaN(M.percent(NaN)), "NaN");
});

test("rate: bytes, then three figures with one decimal under 10", () => {
    assert.deepStrictEqual(M.rate(0), { value: 0, decimals: 0, unit: "B" });
    assert.deepStrictEqual(M.rate(512.4), { value: 512, decimals: 0, unit: "B" });
    assert.deepStrictEqual(M.rate(999.4), { value: 999, decimals: 0, unit: "B" });
    assert.deepStrictEqual(M.rate(999.6), { value: 1, decimals: 1, unit: "kB" }, "999.6 B rounds up: 1.0 kB");
    assert.deepStrictEqual(M.rate(1234), { value: 1.2, decimals: 1, unit: "kB" });
    assert.deepStrictEqual(M.rate(9940), { value: 9.9, decimals: 1, unit: "kB" });
    assert.deepStrictEqual(M.rate(9960), { value: 10, decimals: 0, unit: "kB" }, "9.96 kB is 10, not 10.0");
    assert.deepStrictEqual(M.rate(123456), { value: 123, decimals: 0, unit: "kB" });
    assert.deepStrictEqual(M.rate(999400), { value: 999, decimals: 0, unit: "kB" });
    assert.deepStrictEqual(M.rate(999600), { value: 1, decimals: 1, unit: "MB" }, "999.6 kB is 1.0 MB");
    assert.deepStrictEqual(M.rate(12.5e6), { value: 13, decimals: 0, unit: "MB" });
    assert.deepStrictEqual(M.rate(2.34e9), { value: 2.3, decimals: 1, unit: "GB" });
    assert.deepStrictEqual(M.rate(5e15), { value: 5000, decimals: 0, unit: "TB" }, "the last unit takes any size");
    assert.deepStrictEqual(M.rate(-5), { value: 0, decimals: 0, unit: "B" }, "a negative rate (counter reset) is 0");
    assert.strictEqual(M.rate(undefined), null);
});

test("rate samples bound every rate text", () => {
    const samples = M.rateSamples();
    for (const unit of ["B", "kB", "MB", "GB", "TB"]) {
        assert(samples.some(s => s.unit === unit && s.decimals === 0 && s.value === 888), unit + " whole");
        assert(samples.some(s => s.unit === unit && s.decimals === 1), unit + " one decimal");
    }
    // Every formatted rate has at most three figures (one decimal under 10), as the samples do;
    // the last unit is never reached by a real link.
    for (let v = 1; v < 1e15; v *= 1.37) {
        const r = M.rate(v);
        const figures = r.decimals === 1 ? r.value.toFixed(1).replace(".", "") : String(r.value);
        assert(figures.length <= 3, v + " gives " + JSON.stringify(r));
        assert(r.decimals === 0 || r.value < 10, v + " has a decimal at 10 or more");
    }
});

test("memory: used with one decimal, total rounded up to whole GB from 2 GB", () => {
    const GiB = 1024 ** 3;
    assert.deepStrictEqual(M.memory(6.08 * GiB, 15.3 * GiB), { used: 6.1, total: 16, totalDecimals: 0 });
    assert.deepStrictEqual(M.memory(1 * GiB, 16.02 * GiB), { used: 1, total: 16, totalDecimals: 0 }, "16.02 is 16, not 17");
    assert.deepStrictEqual(M.memory(0.4 * GiB, 1.5 * GiB), { used: 0.4, total: 1.5, totalDecimals: 1 });
    assert.strictEqual(M.memory(1, 0), null);
    assert.strictEqual(M.memory(undefined, 16 * GiB), null);
    assert.strictEqual(M.memoryFraction(4, 16), 0.25);
    assert.strictEqual(M.memoryFraction(20, 16), 1);
    assert(Number.isNaN(M.memoryFraction(4, 0)));
});

test("temperature: no CPU sensor reads 0, Fahrenheit where the region uses it", () => {
    assert.strictEqual(M.temperature(52.4, false), 52);
    assert.strictEqual(M.temperature(52.4, true), 126);
    assert(Number.isNaN(M.temperature(0, false)), "ksystemstats' 0 without a sensor is no reading");
    assert(Number.isNaN(M.temperature(undefined, false)));
    assert(Number.isNaN(M.temperature(250, false)), "nonsense readings are dropped");
    assert.strictEqual(M.temperatureValid(1), true);
});

test("levels: limits, and a value must fall 5 below a limit before the warning ends", () => {
    assert.strictEqual(M.level("cpu", 89, 0), 0);
    assert.strictEqual(M.level("cpu", 90, 0), 1);
    assert.strictEqual(M.level("cpu", 100, 0), 1, "the CPU has no critical level");
    assert.strictEqual(M.level("cpu", 86, 1), 1, "still high just under the limit");
    assert.strictEqual(M.level("cpu", 85, 1), 0, "back at 5 under the limit");
    assert.strictEqual(M.level("memory", 91, 0), 1);
    assert.strictEqual(M.level("temperature", 84, 0), 0);
    assert.strictEqual(M.level("temperature", 85, 0), 1);
    assert.strictEqual(M.level("temperature", 95, 1), 2);
    assert.strictEqual(M.level("temperature", 91, 2), 2, "critical holds within 5 °C");
    assert.strictEqual(M.level("temperature", 90, 2), 1, "then high");
    assert.strictEqual(M.level("temperature", 79, 2), 0, "a big drop ends it at once");
    assert.strictEqual(M.level("cpu", NaN, 1), 0, "no value, no warning");
    assert.strictEqual(M.level("network", 100, 0), 0, "network has no limits");
});

test("interval: 1 to 10 s, x 2 in power saver, x 4 on critical battery", () => {
    assert.strictEqual(M.interval(2000, 0), 2000);
    assert.strictEqual(M.interval(2000, 1), 4000);
    assert.strictEqual(M.interval(2000, 2), 8000);
    assert.strictEqual(M.interval(250, 0), 1000, "never faster than once a second");
    assert.strictEqual(M.interval(60000, 0), 10000);
    assert.strictEqual(M.interval(3000, 7), 12000, "the tier is clamped");
    assert.strictEqual(M.interval(undefined, undefined), 2000);
});

test("shown: the bar's order, only the meters turned on", () => {
    assert.deepStrictEqual(M.shown(true, true, false, false), ["cpu", "memory"]);
    assert.deepStrictEqual(M.shown(false, false, true, true), ["network", "temperature"]);
    assert.deepStrictEqual(M.shown(false, false, false, false), []);
});

console.log("meters: all " + n + " tests passed");
