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
// true; a missing key is the default, false.
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

// 6.8's decoration policies without a title bar (rulesettings.kcfg's choices, which KConfig's
// enum reads by value in any case or by number): "none" (0) and "shadow" (3, the "Only shadow"
// rule: a shadow-only decoration, or the client's own). The others are client-preference (1) and
// server (2).
function policyRemovesTitleBar(value) {
    return ["none", "0", "shadow", "3"].indexOf(String(value).trim().toLowerCase()) >= 0;
}

// Whether a rule removes the title bar: the legacy noborder (6.7.5, and 6.8 before RuleBookSettings
// migrates it to a decoration policy) or one of 6.8's decoration policies without one.
function removesTitleBar(rule) {
    return (sets(rule.noborderrule) && truthy(rule.noborder))
        || (sets(rule.decorationpolicyrule) && policyRemovesTitleBar(rule.decorationpolicy));
}

// Rules::matchWMClass (KWin 6.7.5 and 6.8.0 rules.cpp): unimportant (0) matches every window;
// exact (1), substring (2) and regular expression (3) compare with the class, or "name class" with
// wmclasscomplete, all three case-sensitively (Rules reads wmclass as written, and the window's
// class is its app_id or WM_CLASS as given). A rule's other conditions (role, title, type,
// machine) are not checked: a rule that might apply is taken as applying, so the user's bar is
// never claimed by mistake.
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
