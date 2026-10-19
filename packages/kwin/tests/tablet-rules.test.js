// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of plasmafusion-tablet's Rules.js: the user's window rules that remove a title bar, read
// from kwinrulesrc as QtCore Settings gives its keys. Run: node tests/tablet-rules.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");
const file = path.join(__dirname, "..", "scripts", "plasmafusion-tablet", "contents", "ui", "Rules.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { readRules, keepsNoTitleBar, removesTitleBar, matchesClass } = globalThis;
assert.strictEqual(typeof readRules, "function", "Rules.js does not define readRules");

// A reader over a parsed INI file as QSettings reads it: [General] at the top level, the rest
// as "group/key"; a comma list as a list.
function reader(ini) {
    const values = {};
    let group = "";
    for (const line of ini.split("\n")) {
        const g = line.match(/^\[(.*)\]$/);
        if (g) {
            group = g[1] === "General" ? "" : g[1];
            continue;
        }
        const kv = line.match(/^([^=]+)=(.*)$/);
        if (kv) {
            const v = kv[2].includes(",") ? kv[2].split(",") : kv[2];
            values[(group ? group + "/" : "") + kv[1]] = v;
        }
    }
    return (key) => values[key];
}

// The kwin2-a scenario's rule (apply initially, substring) and a forced one, as the KCM writes them.
const ini = `[1]
Description=KWIN-2: no title bar for kcalc
noborder=true
noborderrule=3
wmclass=kcalc
wmclassmatch=2

[2]
Description=Test: no title bar for kcharselect
noborder=true
noborderrule=2
wmclass=org.kde.kcharselect
wmclassmatch=1

[3]
Description=Opacity only, for every window
opacityactive=90
opacityactiverule=2
wmclassmatch=0

[General]
count=3
rules=1,2,3`;
const rules = readRules(reader(ini));
assert.strictEqual(rules.length, 3);
assert.ok(keepsNoTitleBar(rules, "org.kde.kcalc", "kcalc"));        // substring of the class
assert.ok(keepsNoTitleBar(rules, "org.kde.kcharselect", "kcharselect")); // exact
assert.ok(!keepsNoTitleBar(rules, "org.kde.dolphin", "dolphin"));   // no rule removes its bar
assert.ok(!keepsNoTitleBar(rules, "org.kde.kcharselect2", "x"));     // exact means exact
// One rule only, given as one string; no rules at all; an empty file.
const one = readRules(reader("[1]\nnoborder=true\nnoborderrule=2\nwmclass=konsole\nwmclassmatch=2\n[General]\ncount=1\nrules=1"));
assert.strictEqual(one.length, 1);
assert.ok(keepsNoTitleBar(one, "org.kde.konsole", "konsole"));
assert.deepStrictEqual(readRules(reader("[General]\ncount=0\nrules=")), []);
assert.deepStrictEqual(readRules(() => undefined), []);
// What removes a title bar: noborder with a type that sets it (2-6), or 6.8's decoration policy none.
for (const t of [2, 3, 4, 5, 6]) {
    assert.ok(removesTitleBar({ noborder: "true", noborderrule: String(t) }), `type ${t}`);
}
assert.ok(!removesTitleBar({ noborder: "true", noborderrule: "1" }));      // don't affect
assert.ok(!removesTitleBar({ noborder: "true", noborderrule: "0" }));      // unused
assert.ok(!removesTitleBar({ noborder: "false", noborderrule: "2" }));     // forced to have one
assert.ok(removesTitleBar({ decorationpolicy: "none", decorationpolicyrule: "3" }));
assert.ok(!removesTitleBar({ decorationpolicy: "server", decorationpolicyrule: "2" }));
// Matching the class: unimportant matches all, wmclasscomplete matches "name class", a regular
// expression, and one JavaScript cannot read (taken as applying).
assert.ok(matchesClass({ wmclassmatch: "0" }, "anything", "x"));
assert.ok(matchesClass({ wmclassmatch: "1", wmclass: "kcalc org.kde.kcalc", wmclasscomplete: "true" }, "org.kde.kcalc", "kcalc"));
assert.ok(!matchesClass({ wmclassmatch: "1", wmclass: "org.kde.kcalc", wmclasscomplete: "true" }, "org.kde.kcalc", "kcalc"));
assert.ok(matchesClass({ wmclassmatch: "3", wmclass: "^org\\.kde\\.k(calc|write)$" }, "org.kde.kwrite", "kwrite"));
assert.ok(!matchesClass({ wmclassmatch: "3", wmclass: "^org\\.kde\\.kcalc$" }, "org.kde.kwrite", "kwrite"));
assert.ok(matchesClass({ wmclassmatch: "3", wmclass: "(?<bad" }, "org.kde.kwrite", "kwrite"));
console.log("tablet-rules.test.js: ok");
