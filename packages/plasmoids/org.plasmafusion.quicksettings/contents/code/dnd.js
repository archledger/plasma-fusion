.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Do Not Disturb times (quick settings, G18). "Until tomorrow morning" ends at the next 06:00:
    after midnight that is the coming morning, not the one a day later. The other choices and their
    hours are those of Plasma 6.7's Notifications applet (FullRepresentation.qml: 1 hour, 4 hours,
    this evening at 20:00 before then, Monday 06:00 on Fridays and Saturdays, until turned off as
    one year ahead). Tests: tests/dnd.test.js (not installed).
*/

var MORNING_HOUR = 6;
var EVENING_HOUR = 20;

// The end of "Until tomorrow morning" for a Do Not Disturb started at `now` (a Date).
function untilMorning(now) {
    var end = new Date(now.getTime());
    end.setHours(MORNING_HOUR, 0, 0, 0);
    if (end.getTime() <= now.getTime()) {
        end.setDate(end.getDate() + 1);
    }
    return end;
}

function hoursLater(now, hours) {
    var end = new Date(now.getTime());
    end.setHours(end.getHours() + hours);
    end.setSeconds(0, 0);
    return end;
}

// The choices of "Do not disturb for a while" at `now`, in the stock applet's order: a list of
// {id, until}. "evening" only before 20:00, "monday" only on Fridays and Saturdays (on Sundays
// "morning" is Monday morning). The stock applet hides "tomorrow morning" until 07:00; here it is
// always offered and ends at the coming 06:00 (as the "Until tomorrow" choice did before).
function choices(now) {
    var list = [
        { id: "hour", until: hoursLater(now, 1) },
        { id: "hours4", until: hoursLater(now, 4) }
    ];
    if (now.getHours() < EVENING_HOUR) {
        var evening = new Date(now.getTime());
        evening.setHours(EVENING_HOUR, 0, 0, 0);
        list.push({ id: "evening", until: evening });
    }
    list.push({ id: "morning", until: untilMorning(now) });
    if (now.getDay() >= 5) {
        var monday = new Date(now.getTime());
        monday.setHours(MORNING_HOUR, 0, 0, 0);
        monday.setDate(monday.getDate() + (8 - monday.getDay()));
        list.push({ id: "monday", until: monday });
    }
    var off = new Date(now.getTime());
    off.setFullYear(off.getFullYear() + 1);
    list.push({ id: "off", until: off });
    return list;
}
