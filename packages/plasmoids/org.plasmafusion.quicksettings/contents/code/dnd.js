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
var HOUR = 3600 * 1000;
var DAY = 24 * HOUR;
// A Do Not Disturb that ends further ahead than this is "until turned off" (the stock applet keeps
// such a one a year ahead and shows no end for it either).
var FAR = 100 * DAY;

// The end of "Until tomorrow morning" for a Do Not Disturb started at `now` (a Date).
function untilMorning(now) {
    var end = new Date(now.getTime());
    end.setHours(MORNING_HOUR, 0, 0, 0);
    if (end.getTime() <= now.getTime()) {
        end.setDate(end.getDate() + 1);
    }
    return end;
}

// `hours` of elapsed time after `now`, in whole minutes: adding to the hour of the day (setHours)
// made "For 4 hours" last 5 or 3 hours across a daylight saving change. As keep awake's durations.
// The minute is cut off the time itself: a local setter (setSeconds) in the hour that repeats
// when the clocks go back moves the time to that hour's first pass.
function hoursLater(now, hours) {
    var MINUTE = 60 * 1000;
    return new Date(Math.floor((now.getTime() + hours * HOUR) / MINUTE) * MINUTE);
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

function valid(date) {
    return !!date && typeof date.getTime === "function" && !isNaN(date.getTime());
}

// How the end of a Do Not Disturb running until `until` reads at `now` (a time in ms), and when
// that changes: {kind, refreshAt}. kind: "none" (no end to show: none set, passed, or "until turned
// off"), "time" (within 24 hours: "Until 18:00"), "day" (within a week: "Until Mon 06:00") or
// "date". refreshAt is the time in ms when the kind changes next (the end itself for "time"), or
// -1 when nothing changes ahead (no end, or "until turned off").
function untilLabel(until, now) {
    if (!valid(until)) {
        return { kind: "none", refreshAt: -1 };
    }
    var end = until.getTime();
    var left = end - now;
    if (left <= 0) {
        return { kind: "none", refreshAt: -1 };
    }
    if (left <= DAY) {
        return { kind: "time", refreshAt: end };
    }
    if (left <= 7 * DAY) {
        return { kind: "day", refreshAt: end - DAY };
    }
    if (left <= FAR) {
        return { kind: "date", refreshAt: end - 7 * DAY };
    }
    // "Until turned off": nothing to show, and nothing to look at again for it (the sheet reads the
    // label again whenever Do Not Disturb or its end changes).
    return { kind: "none", refreshAt: -1 };
}

// Why Do Not Disturb is on besides a time, in the stock applet's order: a list of {kind, name,
// reason} with kind "app" (an application holds it: names[i] with reasons[i], which may be
// empty), "mirrored" (screens are mirrored and the settings say to stay quiet then) or
// "fullscreen" (likewise for a focused full-screen window).
function reasons(state) {
    var list = [];
    if (state.byApp) {
        var names = state.names || [];
        var why = state.reasons || [];
        for (var i = 0; i < names.length; ++i) {
            list.push({ kind: "app", name: String(names[i] || ""), reason: String(why[i] || "") });
        }
    }
    if (state.whenMirrored && state.mirrored) {
        list.push({ kind: "mirrored", name: "", reason: "" });
    }
    if (state.whenFullscreen && state.fullscreen) {
        list.push({ kind: "fullscreen", name: "", reason: "" });
    }
    return list;
}
