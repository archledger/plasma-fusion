.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The clipboard sheet's text logic (quick settings, ClipboardPage.qml): search, the one-line
    previews of the entries and the keyboard steps through the list, and what a request for the
    sheet does while the clipboard service loads. The entries themselves come
    from Plasma's own clipboard model (services/Clipboard.qml). Tests: tests/clipboard.test.js
    (not installed).
*/

// Klipper's entry types (HistoryItemType in klipper/historyitem.h, the model's "type" role).
var TEXT = 2;
var IMAGE = 4;
var URL = 8;

// The characters Klipper's own applet shows for blank text (TextItemDelegate.qml).
var BLANKS = { " ": "␣", "\t": "⇥", "\n": "↵", "\r": "" };

// Lower case without accents, so "cafe" finds "Café".
function fold(text) {
    var s = String(text === undefined || text === null ? "" : text).toLowerCase();
    if (typeof s.normalize === "function") {
        s = s.normalize("NFD").replace(/[̀-ͯ]/g, "");
    }
    return s;
}

// Whether an entry's text matches what was typed in the search field: every word of the query
// appears in the text, in any order, as plain text. Klipper's own applet takes the query as a
// regular expression, so a search for "(1" or "c++" found nothing there.
function matches(text, query) {
    var words = fold(query).split(/\s+/).filter(function (w) { return w.length > 0; });
    if (words.length === 0) {
        return true;
    }
    var haystack = fold(text);
    for (var i = 0; i < words.length; ++i) {
        if (haystack.indexOf(words[i]) === -1) {
            return false;
        }
    }
    return true;
}

// The text shown for an entry: runs of white space and line breaks become one space, so two
// lines of the sheet show as much as they can; at most `limit` characters (an ellipsis after a
// cut). Text that is only white space shows Klipper's marks for it (␣ ⇥ ↵) instead of nothing.
function preview(text, limit) {
    var s = String(text === undefined || text === null ? "" : text);
    var max = limit > 0 ? limit : 200;
    var flat = s.replace(/\s+/g, " ").trim();
    if (flat.length === 0) {
        flat = s.replace(/[ \t\n\r]/g, function (c) { return BLANKS[c]; });
    }
    if (flat.length > max) {
        flat = flat.slice(0, max - 1).replace(/\s+$/, "") + "…";
    }
    return flat;
}

// A copied file list (type URL): Klipper's text is the URLs separated by spaces. The names of the
// files, decoded, for the entry's label.
function fileNames(text) {
    var urls = String(text || "").split(" ").filter(function (u) { return u.length > 0; });
    return urls.map(function (u) {
        var path = u.replace(/[?#].*$/, "").replace(/\/+$/, "");
        var name = path.slice(path.lastIndexOf("/") + 1);
        try {
            name = decodeURIComponent(name);
        } catch (e) {
            // a name that is not valid percent-encoding is shown as it is
        }
        return name.length > 0 ? name : u;
    });
}

// The first URL of a copied file list, for its preview picture.
function firstUrl(text) {
    var urls = String(text || "").split(" ").filter(function (u) { return u.length > 0; });
    return urls.length > 0 ? urls[0] : "";
}

// The next current row after an arrow key: `delta` -1 (Up) or +1 (Down) from `index` in a list of
// `count` rows. -1 means "above the list" (the search field takes the focus); the last row stays.
function step(index, delta, count) {
    if (count <= 0) {
        return -1;
    }
    var next = index + delta;
    if (next < 0) {
        return -1;
    }
    return Math.min(next, count - 1);
}

// Whether a key press's text should go to the search field (type to search): printable
// characters only, not control characters (Tab, Return, Escape, Delete give text too).
function typesText(text) {
    if (typeof text !== "string" || text.length === 0) {
        return false;
    }
    var code = text.charCodeAt(0);
    return code >= 32 && code !== 127;
}

// What a request for the clipboard sheet (the clipboard button, Meta+V) does: "sheet" when the
// clipboard service (services/Clipboard.qml, loaded in the background after the widget starts) is
// there, "wait" while it is still loading, "legacy" (Klipper's own pop-up) only when it could not
// load, Plasma's clipboard module missing. Before, a request in the first moments after the shell
// started opened Klipper's pop-up although the service was there a moment later.
function opening(available, loading) {
    if (available) {
        return "sheet";
    }
    return loading ? "wait" : "legacy";
}
