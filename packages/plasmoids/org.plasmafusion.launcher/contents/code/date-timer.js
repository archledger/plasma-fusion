.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Live date for the calendar tiles (dock TaskItem, launcher AppTile): the tile paints today's
    month and day over the art's fixed labels. Qt timers count monotonic time, which pauses across
    system suspend, so a single long "next midnight" interval can fire hours late and leave the
    tile on yesterday's date (seen 2026-10-06 on a laptop resumed from suspend). The timer
    re-arms to the next midnight capped at CAP_MS, and every tick rechecks the date.
    Tests: tests/date-timer.test.js (not installed).
*/

// ms between date rechecks: long enough to be nothing, short enough that a suspend gap is
// noticed within one interval after resume
var CAP_MS = 600000;

// true when now's calendar day differs from today's (the day the tile shows)
function changed(today, now) {
    return today.getFullYear() !== now.getFullYear()
        || today.getMonth() !== now.getMonth()
        || today.getDate() !== now.getDate();
}

// ms until the next local midnight plus 5 s (the original fire point), capped at capMs
function intervalTo(now, capMs) {
    var next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5);
    return Math.max(1000, Math.min(next.getTime() - now.getTime(), capMs));
}
