.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Power mode (quick settings): the profiles the chooser lists, the one the tile's body switches
    to, and the applications holding one, from PowerDevil's power profiles (powerdevil 6.7.5
    PowerProfilesControl). As the stock Power and Battery widget: Performance cannot be chosen while
    the daemon reports a reason that inhibits it (the computer on a lap, running too hot). Tests:
    tests/power.test.js (not installed).
*/

var ORDER = ["power-saver", "balanced", "performance"];

// Performance cannot be chosen: the daemon inhibits it and it is not the active profile (an active
// one stays listed as chosen, so the list shows the truth).
function blocked(profile, active, inhibitionReason) {
    return profile === "performance" && !!inhibitionReason && active !== "performance";
}

// The chooser's rows, in order: the profiles the daemon offers, as [{profile, active, enabled}].
function options(list, active, inhibitionReason) {
    const offered = list || [];
    return ORDER.filter(p => offered.indexOf(p) !== -1).map(p => ({
        profile: p,
        active: p === active,
        enabled: !blocked(p, active, inhibitionReason)
    }));
}

// The profile the tile's body switches to, or "" when there is none. As GNOME's Power Mode toggle:
// the tile is "on" in any profile but Balanced, so a click from there goes back to Balanced, and a
// click on Balanced goes to the last other profile chosen (`last`), Power saver when that one is
// not offered or is an inhibited Performance.
function toggleTarget(list, active, inhibitionReason, last) {
    const offered = list || [];
    const has = p => offered.indexOf(p) !== -1;
    if (active !== "balanced") {
        return has("balanced") && active !== "" ? "balanced" : "";
    }
    for (const p of [last, "power-saver", "performance"]) {
        if (p && p !== "balanced" && has(p) && !blocked(p, active, inhibitionReason)) {
            return p;
        }
    }
    return "";
}

// The holds as [{name, profile}], named by the application (its id when it has no name).
function holds(list) {
    return (list || []).map(h => ({
        name: String(h.Name || h.ApplicationId || ""),
        profile: String(h.Profile || "")
    })).filter(h => h.name !== "" && h.profile !== "");
}
