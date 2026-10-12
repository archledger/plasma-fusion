.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The settings every quick settings widget shares (main.qml sharedKeys): which widget's a widget
    takes when it joins the shell. Each widget keeps the time its shared settings last changed
    (sharedRevision, ms since the epoch; 0 before 0.5.0), and the newest set wins, whichever widget
    loads first after a restart: a bar whose screen was away kept its old settings in its own
    config. Tests: tests/shared.test.js (not installed).
*/

// The widget whose shared settings a joining widget takes: `own` is its revision, `others` the
// revisions of the widgets already there (in the order they came) and `leader` the leader's index
// in them (-1: none). Returns the index in `others` to take them from, or -1 when the joining
// widget's own are the newest (it gives them to the others) or nobody is there. Equal revisions
// (two widgets from before 0.5.0: 0) go to the leader, as before.
function adoptFrom(own, others, leader) {
    const list = others || [];
    let best = leader >= 0 && leader < list.length ? leader : -1;
    for (let i = 0; i < list.length; ++i) {
        if (best === -1 || Number(list[i]) > Number(list[best])) {
            best = i;
        }
    }
    if (best === -1 || Number(own) > Number(list[best])) {
        return -1;
    }
    return best;
}
