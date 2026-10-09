// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/pins.js (not installed). Run: node tests/pins.test.js
// The Ubuntu 2026-10-03 case: with no browser installed, preferred://browser resolves to Kate
// (text/html falls back to its text/plain subclass) and duplicated the explicit Kate pin.
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

// pins.js runs as a script of its own named by its file URL, so V8's coverage (node --test
// --experimental-test-coverage, tools/tests/coverage.sh) maps it to the file. The QML-only
// ".pragma library" line becomes spaces of the same length, which keeps every offset; the
// library's top-level names become globals of this test.
const file = path.join(__dirname, "..", "contents", "code", "pins.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const hiddenDuplicates = globalThis.hiddenDuplicates;
const isRolePin = globalThis.isRolePin;
const appLauncherUrl = globalThis.appLauncherUrl;
assert.notStrictEqual(hiddenDuplicates, undefined, "pins.js does not define hiddenDuplicates");
assert.notStrictEqual(isRolePin, undefined, "pins.js does not define isRolePin");

// A preferred:// pin is a role pin, activities prefix or not; an applications: pin is not.
assert.strictEqual(isRolePin("preferred://browser"), true);
assert.strictEqual(isRolePin("preferred://mailer"), true);
assert.strictEqual(isRolePin("applications:org.kde.kate.desktop"), false);
assert.strictEqual(isRolePin("file:///home/pf/bin/thing.desktop"), false);
assert.strictEqual(isRolePin("[00000000-0000-0000-0000-000000000000]\npreferred://browser"), true);
assert.strictEqual(isRolePin("[abc,def]\napplications:org.kde.kate.desktop"), false);
assert.strictEqual(isRolePin(""), false);
assert.strictEqual(isRolePin(undefined), false);

const rows = (spec) => spec.map(([app, rolePin]) => ({ app: app, rolePin: rolePin }));

// The reproduced defect: the same app pinned twice, once as a preferred:// role pin and once
// explicitly. The role pin's row is hidden, whatever the order.
assert.deepStrictEqual(hiddenDuplicates(rows([
    ["org.kde.dolphin", false], ["org.kde.kate", true], ["org.kde.konsole", false],
    ["org.kde.kontact", false], ["org.kde.kate", false], ["org.kde.elisa", false],
    ["org.kde.gwenview", false], ["org.kde.merkuro.calendar", false], ["org.kde.systemsettings", false],
])), [1], "the preferred://browser row duplicating Kate is hidden");
assert.deepStrictEqual(hiddenDuplicates(rows([["org.kde.kate", true], ["org.kde.kate", false]])), [0]);
assert.deepStrictEqual(hiddenDuplicates(rows([["org.kde.kate", false], ["org.kde.kate", true]])), [1]);

// Rows of the same kind keep the first.
assert.deepStrictEqual(hiddenDuplicates(rows([["org.kde.kate", true], ["org.kde.kate", true]])), [1]);
assert.deepStrictEqual(hiddenDuplicates(rows([["org.kde.kate", false], ["org.kde.kate", false]])), [1]);

// Three of one app: the explicit pin survives, the other two rows go.
assert.deepStrictEqual(hiddenDuplicates(rows([
    ["org.kde.kate", true], ["org.kde.kate", false], ["org.kde.kate", false],
])), [0, 2]);

// Two role pins resolving to the same app (browser and mailer both opening Thunderbird).
assert.deepStrictEqual(hiddenDuplicates(rows([
    ["org.mozilla.Thunderbird", true], ["org.mozilla.Thunderbird", true], ["org.kde.kate", false],
])), [1]);

// Distinct apps are all kept, and so are rows without an app (missing launchers are the
// caller's business).
assert.deepStrictEqual(hiddenDuplicates(rows([
    ["org.kde.dolphin", false], ["org.mozilla.firefox", true], ["", true], ["", false],
    ["org.kde.konsole", false], ["", true],
])), []);
assert.deepStrictEqual(hiddenDuplicates(rows([])), []);


// appLauncherUrl(): one applications: scheme whether the launcher's id has it or not
assert.strictEqual(appLauncherUrl("org.kde.dolphin.desktop"), "applications:org.kde.dolphin.desktop", "plain desktop id");
assert.strictEqual(appLauncherUrl("applications:org.kde.dolphin.desktop"), "applications:org.kde.dolphin.desktop", "id with the scheme (pinned entries, Plasma 6.8)");
assert.strictEqual(appLauncherUrl("file:///home/pf/bin/thing.desktop"), "file:///home/pf/bin/thing.desktop", "a file-backed launcher keeps its URL");

console.log("pins: all checks passed");
