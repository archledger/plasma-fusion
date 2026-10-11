.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Keep awake for a while (quick settings, F7): when a timed Keep awake ends, the minutes it shows
    as left, and when to look at the clock again. Times are milliseconds since the epoch, so a
    suspend in between (which stops Qt's timers) is caught at the next look. Tests:
    tests/keepawake.test.js (not installed).
*/

var MINUTE = 60000;
var HOUR = 60 * MINUTE;
var DAY_MINUTES = 24 * 60;

// The end of "Until HH:MM" chosen at `now` (a Date): `minuteOfDay` minutes after local midnight,
// today, or tomorrow when that time has passed (or is now).
function untilTime(now, minuteOfDay) {
    const m = ((Math.round(minuteOfDay) % DAY_MINUTES) + DAY_MINUTES) % DAY_MINUTES;
    const end = new Date(now.getTime());
    end.setHours(Math.floor(m / 60), m % 60, 0, 0);
    if (end.getTime() <= now.getTime()) {
        end.setDate(end.getDate() + 1);
    }
    return end.getTime();
}

// The time the "Until" chooser offers first: the next quarter hour at least an hour after `now` (a
// Date), as minutes after midnight.
function defaultUntil(now) {
    const later = new Date(now.getTime() + HOUR);
    const m = later.getHours() * 60 + later.getMinutes() + (later.getSeconds() > 0 ? 1 : 0);
    return (Math.ceil(m / 15) * 15) % DAY_MINUTES;
}

// Whole minutes left, rounded up (so "1 min" shows until the end), 0 once `until` has passed.
function minutesLeft(now, until) {
    return until > now ? Math.ceil((until - now) / MINUTE) : 0;
}

// Milliseconds until the minutes left change or the time is up, whichever comes first; 0 when it
// is up.
function nextCheck(now, until) {
    const left = until - now;
    if (left <= 0) {
        return 0;
    }
    return Math.min(left % MINUTE || MINUTE, left);
}
