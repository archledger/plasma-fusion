// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/clipboard.js (not installed). Run: node tests/clipboard.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "clipboard.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { matches, preview, fileNames, firstUrl, step, typesText, opening, TEXT, IMAGE, URL } = globalThis;

// The entry types Klipper's model reports.
assert.deepStrictEqual([TEXT, IMAGE, URL], [2, 4, 8], "Klipper's HistoryItemType values");

// Search: plain text, every word, any case, any order, accents ignored.
assert.ok(matches("Hello World", ""), "an empty query matches everything");
assert.ok(matches("Hello World", "   "), "a blank query matches everything");
assert.ok(matches("Hello World", "world"), "case does not matter");
assert.ok(matches("Hello World", "wor hel"), "every word, in any order");
assert.ok(!matches("Hello World", "hello there"), "every word must appear");
assert.ok(matches("int f(1, 2)", "f(1"), "brackets are plain text, not a regular expression");
assert.ok(matches("learn c++ today", "C++"), "plus signs are plain text");
assert.ok(matches("a.b.c", "a.b"), "a dot is a dot");
assert.ok(!matches("axb", "a.b"), "a dot does not match any character");
assert.ok(matches("Café crème", "cafe creme"), "accents are ignored");
assert.ok(matches("ÉCOLE", "école"), "accented capitals");
assert.ok(matches("line one\nline two", "one two"), "words on other lines");
assert.ok(!matches("", "x"), "an empty entry matches only an empty query");
assert.ok(matches(undefined, ""), "a missing text is empty");

// Previews: white space folded, long text cut, blank text visible.
assert.strictEqual(preview("  Hello\n\n  world\t!  ", 200), "Hello world !", "runs of white space become one space");
assert.strictEqual(preview("abcdefghij", 5), "abcd…", "cut at the limit with an ellipsis");
assert.strictEqual(preview("abcd", 5), "abcd", "short text stays");
assert.strictEqual(preview("abcd efgh", 6), "abcd…", "no space before the ellipsis");
assert.strictEqual(preview("   ", 200), "␣␣␣", "spaces only: Klipper's marks");
assert.strictEqual(preview("\t\n", 200), "⇥↵", "tab and line break only: Klipper's marks");
assert.strictEqual(preview("x".repeat(500)).length, 200, "default limit 200");
assert.strictEqual(preview("<b>bold</b> &amp;", 200), "<b>bold</b> &amp;", "markup is left as text (shown as plain text)");

// Copied files: their names, decoded.
assert.deepStrictEqual(fileNames("file:///home/pf/My%20Photo.jpg file:///home/pf/Documents/"),
    ["My Photo.jpg", "Documents"], "file names, a folder without its slash");
assert.deepStrictEqual(fileNames("https://example.org/a/b?x=1#top"), ["b"], "query and fragment dropped");
assert.deepStrictEqual(fileNames("file:///tmp/%E0%A4%A"), ["%E0%A4%A"], "invalid encoding shown as it is");
assert.deepStrictEqual(fileNames(""), [], "no URLs");
assert.strictEqual(firstUrl("file:///a.png file:///b.png"), "file:///a.png", "first URL for the preview");
assert.strictEqual(firstUrl(""), "", "no first URL");

// Arrow keys through the list; -1 is the search field above it.
assert.strictEqual(step(-1, 1, 3), 0, "Down from the search field: the first row");
assert.strictEqual(step(0, 1, 3), 1, "Down: the next row");
assert.strictEqual(step(2, 1, 3), 2, "Down on the last row stays");
assert.strictEqual(step(1, -1, 3), 0, "Up: the row before");
assert.strictEqual(step(0, -1, 3), -1, "Up on the first row: the search field");
assert.strictEqual(step(0, 1, 0), -1, "an empty list has no row");
assert.strictEqual(step(7, 1, 3), 2, "a row past a shrunk list: the last row");

// Type to search: printable text only.
assert.ok(typesText("a") && typesText("É") && typesText(" ") && typesText("1"), "printable characters");
assert.ok(!typesText("") && !typesText("\t") && !typesText("\r") && !typesText("\u001b") && !typesText("\u007f"),
    "Tab, Return, Escape and Delete are not text");
assert.ok(!typesText(undefined), "no text");

// A request for the sheet while the clipboard service loads waits for it; Klipper's pop-up only
// when the module could not load.
assert.strictEqual(opening(true, false), "sheet", "the service is there: the sheet");
assert.strictEqual(opening(false, true), "wait", "the service is still loading (the shell just started): wait for it");
assert.strictEqual(opening(false, false), "legacy", "the service could not load: Klipper's own pop-up");

console.log("clipboard: all checks passed");
