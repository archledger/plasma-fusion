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
const { readRules, keepsNoTitleBar, removesTitleBar, matchesClass, cascade, truthy, filesKeepNoTitleBar, regexForQt } = globalThis;
// A stand-in for RuleRegex.qml's matches() (QRegularExpression; tests/tablet_regex_test.py), for
// the cases where PCRE and JavaScript agree; undefined where JavaScript cannot read the pattern.
const jsMatch = (p, t) => { try { return new RegExp(p).test(t); } catch (e) { return undefined; } };
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
// 6.8's policy as KConfig's enum reads it: by value in any case, or by number; "Only shadow"
// (shadow, 3) draws no title bar either, client-preference (1) and server (2) do.
for (const p of ["none", "None", "0", "shadow", "Shadow", "3"]) {
    assert.ok(removesTitleBar({ decorationpolicy: p, decorationpolicyrule: "3" }), `policy ${p}`);
}
for (const p of ["client-preference", "1", "server", "Server", "2", undefined]) {
    assert.ok(!removesTitleBar({ decorationpolicy: p, decorationpolicyrule: "3" }), `policy ${p}`);
}
assert.ok(!removesTitleBar({ decorationpolicy: "shadow", decorationpolicyrule: "1" })); // don't affect
// KConfig's Bool: anything but false, no, off or 0 is true; a missing key is false.
for (const v of [true, "true", "True", "1", "yes", "on"]) {
    assert.ok(truthy(v), `bool ${v}`);
}
for (const v of [false, "false", "FALSE", "0", "no", "off", "", undefined, null]) {
    assert.ok(!truthy(v), `bool ${v}`);
}
// KConfig's cascade (the user's file, then ~/.config/kdedefaults and /etc/xdg): a system-wide rule
// counts; a key in the user's file hides the system's; a group only the system's file has is read
// when the user's rule list names it (what the KCM saves after adding a rule beside a system one).
const system = reader("[1]\nnoborder=true\nnoborderrule=3\nwmclass=kcalc\nwmclassmatch=2\n[General]\ncount=1\nrules=1");
const none = () => undefined;
assert.ok(keepsNoTitleBar(readRules(cascade([none, system])), "org.kde.kcalc", "kcalc"));
assert.ok(!keepsNoTitleBar(readRules(cascade([none])), "org.kde.kcalc", "kcalc"));
const userAdds = reader("[2]\nnoborder=true\nnoborderrule=2\nwmclass=org.kde.kcharselect\nwmclassmatch=1\n[General]\ncount=2\nrules=1,2");
const both = readRules(cascade([userAdds, system]));
assert.strictEqual(both.length, 2);
assert.ok(keepsNoTitleBar(both, "org.kde.kcalc", "kcalc"));
assert.ok(keepsNoTitleBar(both, "org.kde.kcharselect", "kcharselect"));
const userList = reader("[2]\nnoborder=true\nnoborderrule=2\nwmclass=org.kde.kcharselect\nwmclassmatch=1\n[General]\ncount=1\nrules=2");
assert.ok(!keepsNoTitleBar(readRules(cascade([userList, system])), "org.kde.kcalc", "kcalc")); // the user's list hides it
const userOff = reader("[1]\nnoborderrule=1");
assert.ok(!keepsNoTitleBar(readRules(cascade([userOff, system])), "org.kde.kcalc", "kcalc")); // the user turned it off
// Matching the class: unimportant matches all, wmclasscomplete matches "name class", a regular
// expression, and one JavaScript cannot read (taken as applying). Exact and substring matching are
// case-sensitive, as in KWin 6.7.5's and 6.8.0's Rules::matchWMClass.
assert.ok(!matchesClass({ wmclassmatch: "1", wmclass: "org.kde.KCalc" }, "org.kde.kcalc", "kcalc"));
assert.ok(!matchesClass({ wmclassmatch: "2", wmclass: "KCalc" }, "org.kde.kcalc", "kcalc"));
assert.ok(matchesClass({ wmclassmatch: "0" }, "anything", "x"));
assert.ok(matchesClass({ wmclassmatch: "1", wmclass: "kcalc org.kde.kcalc", wmclasscomplete: "true" }, "org.kde.kcalc", "kcalc"));
assert.ok(!matchesClass({ wmclassmatch: "1", wmclass: "org.kde.kcalc", wmclasscomplete: "true" }, "org.kde.kcalc", "kcalc"));
assert.ok(matchesClass({ wmclassmatch: "3", wmclass: "^org\\.kde\\.k(calc|write)$" }, "org.kde.kwrite", "kwrite", jsMatch));
assert.ok(!matchesClass({ wmclassmatch: "3", wmclass: "^org\\.kde\\.kcalc$" }, "org.kde.kwrite", "kwrite", jsMatch));
assert.ok(matchesClass({ wmclassmatch: "3", wmclass: "(?<bad" }, "org.kde.kwrite", "kwrite", jsMatch));
// A rule that is off (Enabled=false) is skipped, as Rules::match() does; on by default.
const kcalcRule = "[1]\nnoborder=true\nnoborderrule=3\nwmclass=kcalc\nwmclassmatch=2\n";
const withEnabled = (v) => reader(kcalcRule + (v === null ? "" : "Enabled=" + v + "\n") + "[General]\ncount=1\nrules=1");
assert.ok(!keepsNoTitleBar(readRules(withEnabled("false")), "org.kde.kcalc", "kcalc"));
assert.ok(keepsNoTitleBar(readRules(withEnabled("true")), "org.kde.kcalc", "kcalc"));
assert.ok(keepsNoTitleBar(readRules(withEnabled(null)), "org.kde.kcalc", "kcalc"));
assert.ok(keepsNoTitleBar(readRules(withEnabled("")), "org.kde.kcalc", "kcalc"));
// A key KConfig marks immutable keeps the mark in its name in QtCore Settings: read too.
const locked = reader("[1]\nnoborder[$i]=true\nnoborderrule[$i]=2\nwmclass=kcalc\nwmclassmatch=2\n[General]\nrules[$i]=1");
assert.ok(keepsNoTitleBar(readRules(locked), "org.kde.kcalc", "kcalc"));
// The files together: a system rule the user's file turns off still counts on its own (Settings
// drops KConfig's locks of a file or group, so a locked rule is never missed); one the system's
// own file turns off does not; the user's own rules still count.
const sysRule = reader(kcalcRule + "[General]\ncount=1\nrules=1");
const userOffRule = reader("[1]\nnoborderrule=1");
assert.ok(!keepsNoTitleBar(readRules(cascade([userOffRule, sysRule])), "org.kde.kcalc", "kcalc"));
assert.ok(filesKeepNoTitleBar([userOffRule, sysRule], "org.kde.kcalc", "kcalc"));
assert.ok(!filesKeepNoTitleBar([none, withEnabled("false")], "org.kde.kcalc", "kcalc"));
assert.ok(filesKeepNoTitleBar([sysRule, none], "org.kde.kcalc", "kcalc"));
assert.ok(!filesKeepNoTitleBar([sysRule, none], "org.kde.dolphin", "dolphin"));
assert.ok(!filesKeepNoTitleBar([none], "org.kde.kcalc", "kcalc"));
// A regular expression goes to the matcher (RuleRegex.qml: QRegularExpression, as KWin), with the class
// or "name class"; true and false are its answer, undefined (a pattern it cannot read) and no
// matcher at all are taken as applying.
const re = (p, cls, m) => matchesClass({ wmclassmatch: "3", wmclass: p }, cls, "x", m);
const asked = [];
const recorder = (p, t) => { asked.push([p, t]); return false; };
assert.ok(!re("(?:\\A|\\.)ark\\z", "org.kde.kwrite", recorder));
assert.deepStrictEqual(asked, [["(?:\\A|\\.)ark\\z", "org.kde.kwrite"]]);
assert.ok(re("x", "org.kde.ark", () => true));
assert.ok(re("x", "org.kde.ark", () => undefined));
assert.ok(re("^org\\.kde\\.kcalc$", "org.kde.kwrite")); // no matcher
assert.ok(!matchesClass({ wmclassmatch: "3", wmclass: "^kcalc org", wmclasscomplete: "true" }, "org.kde.kwrite", "kwrite", jsMatch));
assert.ok(matchesClass({ wmclassmatch: "3", wmclass: "^kcalc org", wmclasscomplete: "true" }, "org.kde.kcalc", "kcalc", jsMatch));
// The matcher passed down through the rules and the files.
const arkRule = reader("[4]\nnoborder=true\nnoborderrule=3\nwmclass=(?:\\A|\\.)ark\\z\nwmclassmatch=3\n[General]\nrules=4");
assert.ok(!filesKeepNoTitleBar([arkRule], "org.kde.dolphin", "dolphin", () => false));
assert.ok(filesKeepNoTitleBar([arkRule], "org.kde.ark", "ark", () => true));
assert.ok(filesKeepNoTitleBar([arkRule], "org.kde.dolphin", "dolphin")); // no matcher: applying
// Leading PCRE options as the flags Qt carries over (i and m); the rest as written.
assert.deepStrictEqual(regexForQt("(?i)KCalc"), { source: "KCalc", flags: "i" });
assert.deepStrictEqual(regexForQt("(?mi)^a"), { source: "^a", flags: "mi" });
assert.deepStrictEqual(regexForQt("(?ii)a"), { source: "a", flags: "i" });
assert.deepStrictEqual(regexForQt("a(?i)b"), { source: "a(?i)b", flags: "" });
assert.deepStrictEqual(regexForQt("(?s)a.b"), { source: "(?s)a.b", flags: "" });
// KWin's precedence (CHECK_RULE): of the matching rules, in their order, the first that names the
// title bar decides, also one that leaves it alone (don't affect); a rule this cannot be sure of
// (other conditions, an unread pattern, only 6.8's policy) decides only when it removes the bar.
const R = (o) => Object.assign({ wmclass: "filelight", wmclassmatch: "2" }, o);
const keepsFl = (rules, m) => keepsNoTitleBar(rules, "org.kde.filelight", "filelight", m);
const applyKeep = R({ noborder: "false", noborderrule: "3" });   // apply initially: a title bar
const applyRemove = R({ noborder: "true", noborderrule: "3" });  // apply initially: none
const forceKeep = R({ noborder: "false", noborderrule: "2" });
assert.ok(!keepsFl([applyKeep, applyRemove]));                  // the first decides
assert.ok(keepsFl([applyRemove, applyKeep]));
assert.ok(!keepsFl([forceKeep, applyRemove]));
assert.ok(!keepsFl([R({ noborderrule: "1" }), applyRemove]));    // don't affect: stops too
assert.ok(keepsFl([R({ noborder: "false", noborderrule: "0" }), applyRemove])); // unused: passed over
assert.ok(keepsFl([R({ wmclass: "kcalc", noborder: "false", noborderrule: "2" }), applyRemove])); // no match
assert.ok(keepsFl([R({ enabled: "false", noborder: "false", noborderrule: "2" }), applyRemove]));
for (const cond of [{ titlematch: "1" }, { windowrolematch: "2" }, { clientmachinematch: "1" }, { types: "1" },
                    { tagmatch: "1" }, { hastransientparentmatch: "1" }]) {
    assert.ok(keepsFl([R(Object.assign({ noborder: "false", noborderrule: "2" }, cond)), applyRemove]),
              `not sure of ${JSON.stringify(cond)}`);
}
assert.ok(!keepsFl([R({ types: "4294967295", noborder: "false", noborderrule: "2" }), applyRemove])); // all types
assert.ok(!keepsFl([R({ types: "-1", noborder: "false", noborderrule: "2" }), applyRemove]));
const reKeep = R({ wmclass: "x", wmclassmatch: "3", noborder: "false", noborderrule: "2" });
assert.ok(keepsFl([reKeep, applyRemove], () => undefined));     // a pattern the matcher cannot read
assert.ok(!keepsFl([reKeep, applyRemove], () => true));
assert.ok(keepsFl([reKeep, applyRemove], () => false));
const policyServer = R({ decorationpolicy: "server", decorationpolicyrule: "2" }); // 6.8 only
assert.ok(keepsFl([policyServer, applyRemove]));
assert.ok(!keepsFl([policyServer]));
// noborder over the decoration policy in one rule (6.8 migrates it over): noborder decides.
assert.ok(!removesTitleBar({ noborder: "false", noborderrule: "2", decorationpolicy: "none", decorationpolicyrule: "2" }));
assert.ok(removesTitleBar({ noborder: "true", noborderrule: "2", decorationpolicy: "server", decorationpolicyrule: "2" }));
// The rules' order is the [General] list's.
const ordered = (list) => reader("[6]\nnoborder=false\nnoborderrule=3\nwmclass=filelight\nwmclassmatch=2\n"
    + "[7]\nnoborder=true\nnoborderrule=3\nwmclass=filelight\nwmclassmatch=2\n[General]\nrules=" + list);
assert.ok(!keepsFl(readRules(ordered("6,7"))));
assert.ok(keepsFl(readRules(ordered("7,6"))));
console.log("tablet-rules.test.js: ok");
