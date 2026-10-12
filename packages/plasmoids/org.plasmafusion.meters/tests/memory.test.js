// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/memory.js (not installed): the memory figures of the meters' pop-up and
// the system card, in binary units as Plasma's KFormat and System Monitor show them. Run:
// node tests/memory.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "memory.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { memory } = globalThis;
const GiB = 1024 ** 3;
const MiB = 1024 ** 2;

// What KFormat::formatByteSize(size, 1) and System Monitor print for these sizes (probe on
// Plasma 6.7 / KF 6: 15.3 GiB, 16.0 GiB, 4.1 GiB, 409.6 MiB).
assert.deepStrictEqual(memory(6.08 * GiB, 15.3 * GiB), { used: 6.1, total: 15.3, decimals: 1, unit: "GiB" },
                       "a 16 GB machine: the total the kernel reports, as System Monitor shows it");
assert.deepStrictEqual(memory(15.3 * GiB, 15.3 * GiB), { used: 15.3, total: 15.3, decimals: 1, unit: "GiB" },
                       "full memory: both figures agree with 100% in use");
assert.deepStrictEqual(memory(1 * GiB, 4.06 * GiB), { used: 1, total: 4.1, decimals: 1, unit: "GiB" },
                       "a total just above a whole GiB is not rounded up to the next one");
assert.deepStrictEqual(memory(1.8 * GiB, 2.83 * GiB), { used: 1.8, total: 2.8, decimals: 1, unit: "GiB" });
assert.deepStrictEqual(memory(400 * MiB, 0.75 * GiB), { used: 400, total: 768, decimals: 1, unit: "MiB" },
                       "under 1 GiB both figures in MiB");
assert.deepStrictEqual(memory(100 * GiB, 1536 * GiB), { used: 0.1, total: 1.5, decimals: 1, unit: "TiB" });
assert.deepStrictEqual(memory(20 * GiB, 16 * GiB), { used: 16, total: 16, decimals: 1, unit: "GiB" }, "used never above the total");
assert.deepStrictEqual(memory(-1, 16 * GiB).used, 0);
assert.strictEqual(memory(1, 0), null);
assert.strictEqual(memory(undefined, 16 * GiB), null);
assert.strictEqual(memory("", 16 * GiB), null, "before ksystemstats answered");

// The system card shows the same figures: its copy of memory.js is this one.
const card = path.join(__dirname, "..", "..", "org.plasmafusion.systemcard", "contents", "code", "memory.js");
assert.strictEqual(fs.readFileSync(card, "utf8"), fs.readFileSync(file, "utf8"), "the system card's memory.js differs");
console.log("memory: ok");
