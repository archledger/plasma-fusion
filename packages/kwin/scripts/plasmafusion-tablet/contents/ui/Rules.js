/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The user's window rules that remove a title bar (kwinrulesrc), read for the tablet policy:
    KWin gives scripts no window rules, and a window opened in tablet posture under such a rule
    looks like any window the policy made borderless (docs/parts/kwin-tablet.md, "Windows opened in
    tablet posture get their title bar back"). Tested by packages/kwin/tests/tablet-rules.test.js
    (node).
*/

.pragma library

// Rules::Type (KWin 6.7.5 and 6.8 rules.h): 0 unused, 1 don't affect, then force, apply initially,
// remember, apply now, force temporarily: each of those sets the property.
function sets(type) {
    const t = Number(type);
    return t >= 2 && t <= 6;
}
// A Bool as KConfigGroup::readEntry reads it: anything but false, no, off or 0 (in any case) is
// true; a missing or empty value is the default, false here.
function truthy(value) {
    if (value === undefined || value === null || value === false || value === "") {
        return false;
    }
    return ["false", "no", "off", "0"].indexOf(String(value).trim().toLowerCase()) < 0;
}

// kwinrulesrc as KWin reads it (RuleBookSettings: KSharedConfig::openConfig("kwinrulesrc")),
// KConfig's cascade: the user's file, then those of the XDG config directories (~/.config/
// kdedefaults, /etc/xdg) in their order, a key in an earlier file hiding the same key in the later
// ones. readers: one value() per file, the user's first.
function cascade(readers) {
    return function (k) {
        for (const read of readers) {
            const v = read(k);
            if (v !== undefined && v !== null) {
                return v;
            }
        }
        return undefined;
    };
}

// The rules as plain objects from a reader of kwinrulesrc's keys (QtCore Settings' value(): the
// [General] group's keys at the top level, a rule's as "<group>/<key>"; a comma list may come as a
// list or as one string). A key KConfig marks immutable ("key[$i]=") keeps the mark in its name
// there, and is read too.
function readRules(read) {
    const value = k => {
        const v = read(k);
        return v === undefined || v === null ? read(k + "[$i]") : v;
    };
    let groups = value("rules");
    if (groups === undefined || groups === null || groups === "") {
        groups = [];
    } else if (!Array.isArray(groups) && typeof groups !== "object") {
        groups = String(groups).split(",");
    }
    const list = [];
    for (const g of Array.from(groups)) {
        const id = String(g).trim();
        if (id === "") {
            continue;
        }
        const key = k => value(id + "/" + k);
        list.push({
            enabled: key("Enabled"),
            noborder: key("noborder"), noborderrule: key("noborderrule"),
            decorationpolicy: key("decorationpolicy"), decorationpolicyrule: key("decorationpolicyrule"),
            wmclass: key("wmclass"), wmclassmatch: key("wmclassmatch"), wmclasscomplete: key("wmclasscomplete"),
            types: key("types"), windowrolematch: key("windowrolematch"),
            titlematch: key("titlematch"), clientmachinematch: key("clientmachinematch"),
            tagmatch: key("tagmatch"),
            hastransientparentmatch: key("hastransientparentmatch"),
        });
    }
    return list;
}

// 6.8's decoration policies without a title bar (rulesettings.kcfg's choices, which KConfig's
// enum reads by value in any case or by number): "none" (0) and "shadow" (3, the "Only shadow"
// rule: a shadow-only decoration, or the client's own). The others are client-preference (1) and
// server (2).
function policyRemovesTitleBar(value) {
    return ["none", "0", "shadow", "3"].indexOf(String(value).trim().toLowerCase()) >= 0;
}

// Whether a rule names the title bar: the legacy noborder (6.7.5 reads only it, and 6.8's
// RuleBookSettings migrates it over the decoration policy), or 6.8's decoration policy.
function namesNoBorder(rule) {
    return Number(rule.noborderrule || 0) !== 0;
}
function namesPolicy(rule) {
    return Number(rule.decorationpolicyrule || 0) !== 0;
}

// Whether a rule removes the title bar: its noborder when it names one, else one of 6.8's
// decoration policies without a title bar.
function removesTitleBar(rule) {
    if (namesNoBorder(rule)) {
        return sets(rule.noborderrule) && truthy(rule.noborder);
    }
    return sets(rule.decorationpolicyrule) && policyRemovesTitleBar(rule.decorationpolicy);
}

// Rules::matchWMClass (KWin 6.7.5 and 6.8.0 rules.cpp): unimportant (0) matches every window;
// exact (1), substring (2) and regular expression (3) compare with the class, or "name class" with
// wmclasscomplete, all three case-sensitively (Rules reads wmclass as written, and the window's
// class is its app_id or WM_CLASS as given). A regular expression is KWin's QRegularExpression
// (PCRE), which JavaScript's RegExp reads differently in places, so regexMatch(pattern, text)
// matches it (RuleRegex.qml, with QRegularExpression itself): true or false, or undefined when it
// cannot; then, or without regexMatch, the rule is taken as applying. A rule's other conditions
// are not checked here (keepsNoTitleBar() says how a rule with them counts).
function matchesClass(rule, resourceClass, resourceName, regexMatch) {
    return classMatch(rule, resourceClass, resourceName, regexMatch) !== false;
}
// The same as true, false or undefined (a pattern the matcher cannot read, or no matcher).
function classMatch(rule, resourceClass, resourceName, regexMatch) {
    const match = Number(rule.wmclassmatch || 0);
    if (match === 0) {
        return true;
    }
    const wanted = String(rule.wmclass || "");
    const cls = truthy(rule.wmclasscomplete) ? resourceName + " " + resourceClass : resourceClass;
    if (match === 1) {
        return cls === wanted;
    }
    if (match === 2) {
        return cls.indexOf(wanted) >= 0;
    }
    if (match === 3) {
        return regexMatch ? regexMatch(wanted, cls) : undefined;
    }
    return true;
}

// Whether a rule names nothing but the window class, of what KWin's Rules::match() compares (the
// window types, role, machine, title, tag and having a parent too): its class match is its match.
function onlyByClass(rule) {
    const unimportant = v => v === undefined || v === null || v === "" || Number(v) === 0;
    const t = rule.types; // NET::AllTypesMask (all bits), the default, matches every window
    const allTypes = t === undefined || t === null || t === "" || Number(t) === 4294967295
        || Number(t) === -1;
    return allTypes && unimportant(rule.windowrolematch) && unimportant(rule.titlematch)
        && unimportant(rule.clientmachinematch) && unimportant(rule.tagmatch)
        && unimportant(rule.hastransientparentmatch);
}

// A PCRE pattern as Qt's JavaScript can carry it to a QRegularExpression (a RegExp converts with
// its source unchanged and its i and m flags as options): options PCRE takes at its start, (?i),
// (?m) or both, become those flags, as Qt's JavaScript does not read them.
function regexForQt(pattern) {
    const lead = /^\(\?([im]+)\)/.exec(pattern);
    if (!lead) {
        return { source: pattern, flags: "" };
    }
    return { source: pattern.slice(lead[0].length), flags: Array.from(new Set(lead[1])).join("") };
}

// Whether a rule is on: KWin's Rules::match() skips one whose Enabled is false (default true).
function isEnabled(rule) {
    const on = rule.enabled;
    return on === undefined || on === null || on === "" || truthy(on);
}

// Whether the user's rules keep this window without a title bar, in KWin's precedence
// (WindowRules::checkNoBorder and checkDecorationPolicy, CHECK_RULE in 6.7.5 and 6.8.0): of the
// rules that match the window, in their order, the first that names the title bar decides, also
// one that leaves it alone ("don't affect": Rules::checkSetStop). A rule this cannot be sure of
// (conditions other than the class, a pattern the matcher cannot read, or only 6.8's decoration
// policy, which 6.7.5 does not read) decides only when it removes the bar; one that keeps the bar
// is passed over in case it does not apply, so the user's bar is never claimed by mistake.
function keepsNoTitleBar(rules, resourceClass, resourceName, regexMatch) {
    const cls = String(resourceClass || ""), name = String(resourceName || "");
    for (const r of rules) {
        if (!isEnabled(r) || (!namesNoBorder(r) && !namesPolicy(r))) {
            continue;
        }
        const m = classMatch(r, cls, name, regexMatch);
        if (m === false) {
            continue;
        }
        if (removesTitleBar(r)) {
            return true;
        }
        if (m === true && onlyByClass(r) && namesNoBorder(r)) {
            return false;
        }
    }
    return false;
}

// Whether a rule in kwinrulesrc's files keeps this window without a title bar (readers: one
// value() per file, the user's first): in KConfig's cascade, or in one of the system's files on its
// own. QtCore Settings drops KConfig's marks of an immutable file or group ([$i]), with which an
// administrator's rule wins over the user's file; so a locked rule is never missed, and a user's
// own change to a system rule may be (the window then stays as the policy left it).
function filesKeepNoTitleBar(readers, resourceClass, resourceName, regexMatch) {
    const views = [cascade(readers)].concat(readers.slice(1));
    return views.some(read => keepsNoTitleBar(readRules(read), resourceClass, resourceName,
                                              regexMatch));
}
