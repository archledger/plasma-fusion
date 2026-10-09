// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/audio.js (not installed). Run: node tests/audio.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "audio.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const match = globalThis.match;
assert.notStrictEqual(match, undefined, "audio.js does not define match");

const never = () => false;
const firefox = { pid: 100, appName: "Firefox", portalAppId: "" };
const elisa = { pid: 200, appName: "Elisa", portalAppId: "" };
const chromeHelper = { pid: 301, appName: "Google Chrome", portalAppId: "" };
const flatpak = { pid: 2, appName: "Spotify", portalAppId: "com.spotify.Client" };
const all = [firefox, elisa, chromeHelper, flatpak];

// by process id: the app's own stream, remembered as a process-id match
let r = match(all, never, "org.kde.elisa", 200, "Elisa");
assert.deepStrictEqual(r.streams, [elisa], "process id");
assert.strictEqual(r.pidMatch, "Elisa", "a process-id match is remembered");

// by portal app id first (a sandboxed app's pid is the sandbox's)
r = match(all, never, "com.spotify.Client", 9999, "Spotify");
assert.deepStrictEqual(r.streams, [flatpak], "portal app id");
assert.strictEqual(r.pidMatch, "", "no process-id match for a portal match");
// a portal stream never matches by process id
r = match(all, never, "", 2, "Other");
assert.deepStrictEqual(r.streams, [], "a portal stream's pid is not the app's");

// a helper process's stream: by application name
r = match(all, never, "google-chrome", 300, "Google Chrome");
assert.deepStrictEqual(r.streams, [chromeHelper], "name fallback");
assert.strictEqual(r.pidMatch, "", "no process-id match for a name match");

// two instances: once an app was matched by pid, the quiet instance does not take the other's stream
r = match(all, name => name === "Firefox", "firefox", 101, "Firefox");
assert.deepStrictEqual(r.streams, [], "a second instance after a pid match");
r = match(all, never, "firefox", 101, "Firefox");
assert.deepStrictEqual(r.streams, [firefox], "before any pid match the name still matches");

// nothing to match
assert.deepStrictEqual(match([], never, "org.kde.elisa", 200, "Elisa").streams, [], "no streams");
assert.deepStrictEqual(match(all, never, "", 0, "").streams, [], "no id, pid or name");
console.log("audio.js: all checks passed");
