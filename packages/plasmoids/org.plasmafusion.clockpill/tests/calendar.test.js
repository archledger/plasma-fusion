// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, "../contents/code/calendar.js"), "utf8")
    .replace(/^\.pragma library$/m, ""), context);

test("Open calendar goes to the day only when KOrganizer is the calendar application", () => {
    assert.equal(context.openAction(false, true, true, "KOrganizer"), "korganizer-open");
    // KOrganizer installed, another calendar application in use: open that one, KOrganizer untouched
    assert.equal(context.openAction(false, true, true, "Merkuro Calendar"), "launch");
    assert.equal(context.openAction(false, false, true, "Merkuro Calendar"), "launch");
    assert.equal(context.openAction(false, false, false, ""), "none");
});
test("Add event uses KOrganizer's editor when it can be started", () => {
    assert.equal(context.openAction(true, true, true, "Merkuro Calendar"), "korganizer-editor");
    assert.equal(context.openAction(true, true, true, "KOrganizer"), "korganizer-editor");
    assert.equal(context.openAction(true, false, true, "Merkuro Calendar"), "launch");
});
