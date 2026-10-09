// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, "../contents/code/formats.js"), "utf8")
    .replace(/^\.pragma library$/m, ""), context);

test("seconds are opt-in and preserve the region's AM/PM order", () => {
    assert.equal(context.timeFormat("h:mm AP", 1, "en_US"), "h:mm AP");
    assert.equal(context.timeFormat("h:mm AP", 1, "en_US", true), "h:mm:ss AP");
    assert.equal(context.timeFormat("APh:mm", 1, "zh_TW", true), "APh:mm:ss");
});
test("seconds respect forced hour cycle and quoted locale text", () => {
    assert.equal(context.timeFormat("h:mm AP", 2, "en_US", true), "HH:mm:ss");
    assert.equal(context.timeFormat("HH:mm", 0, "ko_KR", true), "AP h:mm:ss");
    assert.equal(context.timeFormat("HH 'h' mm", 1, "fr_CA", true), "HH 'h' mm:ss");
});
