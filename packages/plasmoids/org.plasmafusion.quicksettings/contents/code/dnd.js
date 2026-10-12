.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Do Not Disturb times (quick settings, G18). "Until tomorrow" ends at the next 06:00: after
    midnight that is the coming morning, not the one a day later. Tests: tests/dnd.test.js (not
    installed).
*/

var MORNING_HOUR = 6;

// The end of "Until tomorrow" for a Do Not Disturb started at `now` (a Date).
function untilMorning(now) {
    var end = new Date(now.getTime());
    end.setHours(MORNING_HOUR, 0, 0, 0);
    if (end.getTime() <= now.getTime()) {
        end.setDate(end.getDate() + 1);
    }
    return end;
}
