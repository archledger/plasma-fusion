.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Power mode (quick settings): the profiles the tile cycles through and the applications holding
    one, from PowerDevil's power profiles (powerdevil 6.7.5 PowerProfilesControl). As the stock Power
    and Battery widget: Performance is not offered while the daemon reports a reason that inhibits
    it (the computer on a lap, running too hot). Tests: tests/power.test.js (not installed).
*/

var ORDER = ["power-saver", "balanced", "performance"];

// The profiles to cycle through, in order: those the daemon offers, without Performance while it
// is inhibited (unless it is the active one, so the cycle can leave it).
function choices(list, active, inhibitionReason) {
    const offered = list || [];
    return ORDER.filter(p => offered.indexOf(p) !== -1
        && !(p === "performance" && inhibitionReason && active !== "performance"));
}

// The profile after the active one, or "" when there is nothing to switch to.
function next(list, active, inhibitionReason) {
    const c = choices(list, active, inhibitionReason);
    if (c.length === 0) {
        return "";
    }
    const at = c.indexOf(active);
    const n = c[(at + 1) % c.length];
    return n === active ? "" : n;
}

// The holds as [{name, profile}], named by the application (its id when it has no name).
function holds(list) {
    return (list || []).map(h => ({
        name: String(h.Name || h.ApplicationId || ""),
        profile: String(h.Profile || "")
    })).filter(h => h.name !== "" && h.profile !== "");
}
