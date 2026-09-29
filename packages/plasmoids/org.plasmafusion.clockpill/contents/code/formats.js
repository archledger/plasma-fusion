/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

// Tokens of a QLocale format string that are not the given letters: the year, quoted literals,
// punctuation. Used to trim what is left after the year is removed.
function _hasField(token, letters) {
    return new RegExp("[" + letters + "]").test(token.replace(/'[^']*'/g, ""));
}

function _trimTokens(format, letters) {
    const tokens = format.split(/\s+/).filter(t => t.length > 0);
    while (tokens.length > 0 && !_hasField(tokens[0], letters)) {
        tokens.shift();
    }
    while (tokens.length > 0 && !_hasField(tokens[tokens.length - 1], letters)) {
        tokens.pop();
    }
    return tokens.join(" ");
}

// Removes the year (with a quoted literal just before it, as in Spanish "'de' yyyy", and a
// CJK year suffix) from a date format.
function _withoutYear(format) {
    return format.replace(/('[^']*'\s*)?y+\s*(年|년|'年'|'년')?/g, " ");
}

// The top bar's date: weekday, day and month without the year, in the order and with the
// separators of the region's long date format ("Mon 28 Sep" in en_GB, "Mon Sep 28" in en_US,
// "Mo. 28. Sept." in de_DE, "lun 28 de sept" in es_ES). Commas are dropped as on the board.
function shortDateFormat(locale, longFormat) {
    let f = _withoutYear(longFormat);
    f = f.replace(/dddd/g, "ddd").replace(/MMMM/g, "MMM");
    f = f.replace(/[,،，、]/g, " ");
    // CJK formats have no space before the weekday: "M月d日ddd" reads better as "M月d日(ddd)".
    f = f.replace(/(日|일)(ddd)/, "$1 ($2)");
    f = _trimTokens(f, "dM");
    return f.length > 0 ? f : "ddd d MMM";
}

// The calendar header's date: the long date without the weekday ("28 September 2026").
function longDateWithoutWeekday(longFormat) {
    let f = longFormat.replace(/d{4}/g, " ");
    f = f.replace(/\s+[,،，、]/g, ",");
    f = _trimTokens(f.replace(/^[\s,،，、]+|[\s,،，、]+$/g, ""), "dMy");
    return f.length > 0 ? f : "d MMMM yyyy";
}

// Applies `fn` to the parts of a QLocale format that are not quoted literals.
function _mapUnquoted(format, fn) {
    return format.split(/('[^']*')/).map((part, i) => i % 2 === 1 ? part : fn(part)).join("");
}

// Hours and minutes. use24h: 0 = 12-hour, 1 = as the region, 2 = 24-hour (Qt.CheckState values,
// the stock digital clock's setting). The region's own short time format is used whenever it
// already has the wanted hour cycle, so the order, the separators and the place of the AM/PM
// marker stay the region's ("2:49 PM", "14:49", "오후 2:49", "下午2:49", "14 h 49").
function timeFormat(shortTimeFormat, use24h, localeName) {
    // Short formats have no seconds; drop them should a region have them.
    const format = _mapUnquoted(shortTimeFormat, part => part.replace(/[.:\s]*s+/g, "")) || "HH:mm";
    let regionAp = false;
    _mapUnquoted(format, part => {
        regionAp = regionAp || /[Aa]/.test(part);
        return part;
    });
    if (use24h === 1 || (use24h === 0 && regionAp) || (use24h === 2 && !regionAp)) {
        return format;
    }
    if (use24h === 2) {
        // A 12-hour region shown with 24 hours: drop the marker, two-digit hours ("09:05").
        return _mapUnquoted(format, part => part.replace(/[Aa][Pp]?/g, "").replace(/h+/g, "HH"))
            .replace(/\s{2,}/g, " ").trim();
    }
    // A 24-hour region shown with 12 hours: "2:49 PM"; Chinese, Japanese and Korean put the
    // marker first, as their own 12-hour formats do.
    const hours = _mapUnquoted(format, part => part.replace(/[Hh]+/g, "h"));
    const language = String(localeName || "").split(/[_-]/)[0];
    if (language === "ko") {
        return "AP " + hours;
    }
    if (language === "zh" || language === "ja") {
        return "AP" + hours;
    }
    return hours + " AP";
}
