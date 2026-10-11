// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the Places view's helpers in contents/code/launcher.js (not installed).
// Run: node tests/places.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "launcher.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { placeKind, placePath } = globalThis;
assert.strictEqual(typeof placeKind, "function", "launcher.js does not define placeKind");
assert.strictEqual(typeof placePath, "function", "launcher.js does not define placePath");
const glyphs = vm.runInThisContext("glyphs");

// The file manager's standard places (KFilePlacesModel's defaults), by URL: ComputerModel gives
// their icons as QIcons, which QML cannot name.
const home = "file:///home/pf";
const folders = { home, desktop: home + "/Desktop", documents: home + "/Documents", downloads: home + "/Downloads",
                  music: home + "/Music", pictures: home + "/Pictures", videos: home + "/Videos" };
assert.strictEqual(placeKind(home, folders).glyph, "home", "home folder");
assert.strictEqual(placeKind(home + "/", folders).glyph, "home", "home folder with a trailing slash");
assert.strictEqual(placeKind(home + "/Documents", folders).glyph, "doc", "documents");
assert.strictEqual(placeKind(home + "/Downloads", folders).glyph, "download", "downloads");
assert.strictEqual(placeKind(home + "/Pictures", folders).glyph, "image", "pictures");
assert.strictEqual(placeKind(home + "/Desktop", folders).glyph, "desktop", "desktop");
assert.strictEqual(placeKind(home + "/Documents/Taxes", folders).glyph, "folder", "a folder inside Documents");
assert.strictEqual(placeKind("trash:/", folders).glyph, "trash", "trash");
assert.strictEqual(placeKind("remote:/", folders).glyph, "network", "network");
assert.strictEqual(placeKind("recentlyused:/files?path=/&modified=today", folders).glyph, "clock", "modified today");
assert.strictEqual(placeKind("file:///", folders).glyph, "drive", "root folder");
// Removable drives: mounted under /run/media, or not mounted yet (no URL at all).
assert.strictEqual(placeKind("file:///run/media/pf/STICK", folders).glyph, "drive", "USB stick");
assert.strictEqual(placeKind("", folders).glyph, "drive", "card not mounted");
assert.strictEqual(placeKind("file:///home/pf/Projects", folders, "drive-removable-media").glyph, "drive", "icon name when given");
assert.strictEqual(placeKind(home + "/Projects", folders).glyph, "folder", "a user's own place");
assert.strictEqual(placeKind(home + "/Projects").glyph, "folder", "no standard folders known");
for (const url of [home, home + "/Documents", home + "/Downloads", home + "/Desktop", "trash:/", "remote:/", "", "file:///",
                   "recentlyused:/", home + "/x"]) {
    const kind = placeKind(url, folders);
    assert.ok(glyphs[kind.glyph], `glyph ${kind.glyph} for ${url} is drawn`);
    assert.match(kind.color, /^#[0-9a-f]{6}$/, `colour for ${url}`);
}

// Second lines.
assert.strictEqual(placePath(home, home, ""), "~", "the home folder is ~");
assert.strictEqual(placePath(home + "/Documents", home, ""), "~/Documents", "below home");
assert.strictEqual(placePath(home + "/My%20Files/", home + "/", ""), "~/My Files", "decoded, trailing slashes dropped");
assert.strictEqual(placePath("file:///home/pfx/Music", home, ""), "/home/pfx/Music", "a sibling of home is not ~");
assert.strictEqual(placePath("file:///", home, ""), "/", "the root folder");
assert.strictEqual(placePath("file:///run/media/pf/STICK", home, ""), "/run/media/pf/STICK", "a mount point");
assert.strictEqual(placePath("trash:/", home, "Places"), "Places", "a non-local place shows the fallback");
assert.strictEqual(placePath("", home, "/run/media/pf/CARD"), "/run/media/pf/CARD", "a drive: its mount point");
assert.strictEqual(placePath("file:///home/pf/%E0%A4", home, ""), "~/%E0%A4", "a malformed escape does not throw");
console.log("places: ok");
