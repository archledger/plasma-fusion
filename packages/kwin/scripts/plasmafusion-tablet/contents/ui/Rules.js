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
function truthy(value) {
    return value === true || String(value).toLowerCase() === "true";
}

// The rules as plain objects from a reader of kwinrulesrc's keys (QtCore Settings' value(): the
// [General] group's keys at the top level, a rule's as "<group>/<key>"; a comma list may come as a
// list or as one string).
function readRules(value) {
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
            noborder: key("noborder"), noborderrule: key("noborderrule"),
            decorationpolicy: key("decorationpolicy"), decorationpolicyrule: key("decorationpolicyrule"),
            wmclass: key("wmclass"), wmclassmatch: key("wmclassmatch"), wmclasscomplete: key("wmclasscomplete"),
        });
    }
    return list;
}

// Whether a rule removes the title bar: the legacy noborder (6.7.5, and 6.8 before migration) or
// 6.8's decoration policy "none".
function removesTitleBar(rule) {
    return (sets(rule.noborderrule) && truthy(rule.noborder))
        || (sets(rule.decorationpolicyrule) && String(rule.decorationpolicy).toLowerCase() === "none");
}

// Rules::matchWMClass (KWin 6.7.5 rules.cpp): unimportant (0) matches every window; exact (1),
// substring (2) and regular expression (3) compare with the class, or "name class" with
// wmclasscomplete. A rule's other conditions (role, title, type, machine) are not checked: a rule
// that might apply is taken as applying, so the user's bar is never claimed by mistake.
function matchesClass(rule, resourceClass, resourceName) {
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
        try {
            return new RegExp(wanted).test(cls);
        } catch (e) {
            return true; // a pattern JavaScript cannot read: taken as applying
        }
    }
    return true;
}

// Whether one of the user's rules keeps this window without a title bar.
function keepsNoTitleBar(rules, resourceClass, resourceName) {
    return rules.some(r => removesTitleBar(r) && matchesClass(r, String(resourceClass || ""), String(resourceName || "")));
}
