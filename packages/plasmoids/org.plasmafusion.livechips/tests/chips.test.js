// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/chips.js (not installed). Run: node tests/chips.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "chips.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { capsule, argument, portalKind, remoteLogins, cameraApps, timeLeft, tint, GLYPHS, PRIVACY_ORDER,
        newReads, readStarted, readForgotten, readCurrent, layoutKey, island, islandRows, iconGuess, ISLAND_COLOURS } = globalThis;

let checks = 0;
function check(fn) {
    fn();
    checks += 1;
}

// The capsule: one kind takes its tint, several share a neutral capsule, in the board's order.
check(() => assert.deepStrictEqual(capsule({}), { kinds: [], tintKind: "" }, "nothing in use: no capsule"));
check(() => assert.deepStrictEqual(capsule({ microphone: true }), { kinds: ["microphone"], tintKind: "microphone" }, "one kind: its tint"));
check(() => assert.deepStrictEqual(capsule({ microphone: true, camera: true }), { kinds: ["camera", "microphone"], tintKind: "" },
    "camera and microphone: camera first, neutral (the board's order)"));
check(() => assert.deepStrictEqual(capsule({ ssh: true, remote: true, screen: true }).kinds, ["remote", "screen", "ssh"],
    "the most serious first"));
check(() => assert.deepStrictEqual(capsule({ microphone: false, ssh: true }).kinds, ["ssh"], "a false kind is not in use"));
for (const kind of PRIVACY_ORDER) {
    check(() => assert.ok(GLYPHS[kind] && /^M/.test(GLYPHS[kind]), "a glyph for " + kind));
    check(() => assert.ok(tint(kind, true) && tint(kind, false), "a dark and a light tint for " + kind));
}
check(() => assert.deepStrictEqual(tint("microphone", true), { r: 242 / 255, g: 166 / 255, b: 90 / 255, a: 0.2 }, "the Colors board's badge"));
check(() => assert.strictEqual(tint("nothing", true), null, "no tint for an unknown kind"));

// %1 from a translated message, with the pattern from the sender's own catalogue.
const M = "\u0001";
check(() => assert.strictEqual(argument("Sharing contents to Firefox", "Sharing contents to " + M, M), "Firefox", "the app's name"));
check(() => assert.strictEqual(argument("Inhalte werden für Zoom freigegeben", "Inhalte werden für " + M + " freigegeben", M), "Zoom",
    "a pattern with text after the argument"));
check(() => assert.strictEqual(argument("Time recorded: 0:42\nClick to finish recording",
    "Time recorded: " + M + "\nClick to finish recording", M), "0:42", "Spectacle's time, over two lines"));
check(() => assert.strictEqual(argument("Time recorded: 1:02:03\nClick to stop rendering early (this will lose data)",
    "Time recorded: " + M + "\nClick to finish recording", M), "", "rendering: not the recording message"));
check(() => assert.strictEqual(argument("Sharing contents to Firefox", "Sharing contents to %1", M), "", "a pattern without the marker"));
check(() => assert.strictEqual(argument("", "Sharing contents to " + M, M), "", "no text"));
check(() => assert.strictEqual(argument("Sharing", "Sharing contents to " + M, M), "", "shorter than the pattern"));

check(() => assert.strictEqual(portalKind("media-record"), "screen", "screen casting"));
check(() => assert.strictEqual(portalKind("krfb"), "remote", "remote control"));
check(() => assert.strictEqual(portalKind("dialog-information"), "", "another portal item"));

// systemd-logind: remote sessions that are not closing, oldest first.
const sessions = [
    { id: "2", user: "test", remote: false, remoteHost: "", service: "sddm", state: "active", since: 1000 },
    { id: "41", user: "wisbfime", remote: true, remoteHost: "10.0.10.54", service: "sshd", state: "active", since: 2000000 },
    { id: "40", user: "test", remote: true, remoteHost: "100.78.204.1", service: "tailscaled", state: "online", since: 1000000 },
    { id: "42", user: "test", remote: true, remoteHost: "10.0.10.9", service: "sshd", state: "closing", since: 3000000 },
    { id: "43", user: "guest", remote: true, remoteHost: "10.0.10.7", service: "xrdp-sesman", state: "active", since: 4000000 }
];
const logins = remoteLogins(sessions);
check(() => assert.deepStrictEqual(logins.map((l) => l.id), ["40", "41", "43"], "remote, not closing, oldest first"));
check(() => assert.deepStrictEqual(logins[1], { id: "41", user: "wisbfime", host: "10.0.10.54", ssh: true, since: 2000 },
    "user, host, ssh and the start in milliseconds"));
check(() => assert.strictEqual(logins[0].ssh, true, "Tailscale SSH is SSH"));
check(() => assert.strictEqual(logins[2].ssh, false, "another remote login is not SSH"));
check(() => assert.deepStrictEqual(remoteLogins([]), [], "no sessions"));

// pw-dump: the apps whose video streams are linked from a camera.
const dump = [
    { id: 30, type: "PipeWire:Interface:Node", info: { props: { "media.class": "Video/Source", "media.role": "Camera", "node.nick": "Integrated Camera" } } },
    { id: 31, type: "PipeWire:Interface:Node", info: { props: { "media.class": "Video/Source", "device.api": "v4l2" } } },
    { id: 32, type: "PipeWire:Interface:Node", info: { props: { "media.class": "Video/Source", "node.name": "xdg-desktop-portal-kde" } } },
    { id: 50, type: "PipeWire:Interface:Node", info: { props: { "media.class": "Stream/Input/Video", "application.name": "Zoom" } } },
    { id: 51, type: "PipeWire:Interface:Node", info: { props: { "media.class": "Stream/Input/Video", "application.name": "Firefox" } } },
    { id: 52, type: "PipeWire:Interface:Node", info: { props: { "media.class": "Stream/Input/Video", "application.name": "OBS" } } },
    { id: 53, type: "PipeWire:Interface:Node", info: { props: { "media.class": "Stream/Input/Audio", "application.name": "Audacity" } } },
    { id: 60, type: "PipeWire:Interface:Link", info: { "output-node-id": 30, "input-node-id": 50 } },
    { id: 61, type: "PipeWire:Interface:Link", info: { "output-node-id": 31, "input-node-id": 51 } },
    { id: 62, type: "PipeWire:Interface:Link", info: { "output-node-id": 30, "input-node-id": 50 } },
    { id: 63, type: "PipeWire:Interface:Link", info: { "output-node-id": 32, "input-node-id": 52 } },
    { id: 64, type: "PipeWire:Interface:Link", info: { "output-node-id": 30, "input-node-id": 53 } },
    { id: 65, type: "PipeWire:Interface:Link", info: null }
];
check(() => assert.deepStrictEqual(cameraApps(dump), ["Zoom", "Firefox"],
    "camera readers once each; a screen-cast source and an audio stream are not the camera"));
check(() => assert.deepStrictEqual(cameraApps(null), [], "no dump"));
check(() => assert.deepStrictEqual(cameraApps([]), [], "an empty graph"));

// Keep awake: whole minutes left, rounded up.
check(() => assert.deepStrictEqual(timeLeft(24 * 60000, 0), { hours: 0, minutes: 24, total: 24 }, "24 min"));
check(() => assert.deepStrictEqual(timeLeft(30000, 0), { hours: 0, minutes: 1, total: 1 }, "30 s left: 1 min"));
check(() => assert.deepStrictEqual(timeLeft(65 * 60000, 0), { hours: 1, minutes: 5, total: 65 }, "1 h 5 min"));
check(() => assert.deepStrictEqual(timeLeft(0, 5000), { hours: 0, minutes: 0, total: 0 }, "ended: nothing left"));

// Status item reads: a reply after the item unregistered is dropped.
const reads = newReads();
const first = readStarted(reads, "a/StatusNotifierItem");
check(() => assert.ok(readCurrent(reads, "a/StatusNotifierItem", first), "a reply to a read of a registered item is taken"));
const again = readStarted(reads, "a/StatusNotifierItem");
check(() => assert.ok(readCurrent(reads, "a/StatusNotifierItem", first) && readCurrent(reads, "a/StatusNotifierItem", again),
    "two reads of the item: both replies are taken (a slow reply is not lost to a newer read)"));
readForgotten(reads, "a/StatusNotifierItem");
check(() => assert.ok(!readCurrent(reads, "a/StatusNotifierItem", first), "the item unregistered while it was read: its reply is dropped"));
const reborn = readStarted(reads, "a/StatusNotifierItem");
check(() => assert.ok(!readCurrent(reads, "a/StatusNotifierItem", first) && readCurrent(reads, "a/StatusNotifierItem", reborn),
    "the name registers again: the old read's reply is still dropped, the new one taken"));

// The chips' places change with the set of chips, not with the running time.
check(() => assert.strictEqual(layoutKey(["ssh"], { time: "0:41" }, false), layoutKey(["ssh"], { time: "0:42" }, false),
    "the recording's time does not change the layout"));
check(() => assert.notStrictEqual(layoutKey(["ssh"], null, false), layoutKey(["ssh"], { time: "0:01" }, false),
    "a recording that starts does"));
check(() => assert.notStrictEqual(layoutKey(["ssh"], null, false), layoutKey(["microphone", "ssh"], null, false), "a new kind does"));

// The island (board Island.dc.html): privacy first, then a recording, Keep awake and the music; the
// first two show; in a full-screen window only the privacy kinds, as dots.
check(() => assert.deepStrictEqual(island({ privacy: [], recording: false, keepAwake: false, music: false }), { mode: "none", items: [], dots: [] },
    "nothing going on: no island"));
check(() => assert.deepStrictEqual(island({ privacy: ["camera", "microphone"] }), { mode: "compact", items: ["privacy"], dots: ["camera", "microphone"] },
    "a call: the privacy kinds"));
check(() => assert.deepStrictEqual(island({ privacy: ["camera", "microphone"], music: true }).items, ["privacy", "music"],
    "a call and music: the music in the bubble"));
check(() => assert.deepStrictEqual(island({ privacy: ["microphone"], recording: true, keepAwake: true, music: true }).items, ["privacy", "recording"],
    "four things: the privacy kinds and the recording; the rest waits in the bar"));
check(() => assert.deepStrictEqual(island({ privacy: [], recording: false, keepAwake: true, music: true }).items, ["keepawake", "music"],
    "no privacy kind: Keep awake first, then the music"));
check(() => assert.deepStrictEqual(island({ privacy: [], music: true }).items, ["music"], "music alone"));
check(() => assert.deepStrictEqual(island({ privacy: ["camera", "microphone"], recording: true, music: true, fullScreen: true }),
    { mode: "dots", items: [], dots: ["camera", "microphone"] }, "full screen: only the privacy dots"));
check(() => assert.deepStrictEqual(island({ privacy: [], recording: true, music: true, fullScreen: true }).mode, "none",
    "full screen without a privacy kind: no island"));
check(() => assert.deepStrictEqual(Object.keys(ISLAND_COLOURS).sort(), ["camera", "microphone", "recording", "remote", "screen", "ssh"],
    "a colour for every kind"));
check(() => assert.strictEqual(ISLAND_COLOURS.camera, "#7fd99c", "the dark scheme's ForegroundPositive"));

// The opened island's rows: one per app, its kinds in order, the action of the most serious one.
{
    const mics = [{ name: "Firefox", muted: false }, { name: "Zoom", muted: true }];
    const portal = [{ key: "s1", kind: "screen", app: "OBS Studio" }, { key: "r1", kind: "remote", app: "Krfb" }, { key: "s2", kind: "screen", app: "firefox" }];
    const rows = islandRows(mics, ["Firefox"], true, [], portal, [{ id: "7", user: "ana", host: "10.0.0.2" }]);
    check(() => assert.deepStrictEqual(rows.map((r) => r.app), ["Krfb", "Firefox", "OBS Studio", "Zoom", "ana@10.0.0.2"],
        "remote control first, then the screen, the camera and microphone, SSH last"));
    const ff = rows.find((r) => r.app === "Firefox");
    check(() => assert.deepStrictEqual([ff.kinds, ff.action, ff.session, ff.microphone], [["screen", "camera", "microphone"], "stop", "s2", 0],
        "Firefox: one row (its name in any case), Stop sharing before Mute"));
    check(() => assert.deepStrictEqual([rows[0].action, rows[0].session], ["end", "r1"], "remote control: End"));
    const zoom = rows.find((r) => r.app === "Zoom");
    check(() => assert.deepStrictEqual([zoom.kinds, zoom.action, zoom.microphone], [["microphone"], "unmute", 1], "a muted app: Unmute"));
    check(() => assert.deepStrictEqual([rows[4].kinds, rows[4].action, rows[4].login], [["ssh"], "", "7"], "a login: no action"));
}
check(() => assert.deepStrictEqual(islandRows([], [], true, ["Integrated Camera"], [], []).map((r) => [r.app, r.kinds]), [["Integrated Camera", ["camera"]]],
    "a camera whose app is not known: the camera's name"));
check(() => assert.deepStrictEqual(islandRows([], [], false, ["Integrated Camera"], [], []), [], "a camera not in use: no row"));
check(() => assert.deepStrictEqual([iconGuess("Firefox"), iconGuess(" Google  Chrome "), iconGuess("")], ["firefox", "google-chrome", ""],
    "an icon name from an app's name"));

console.log("chips.test.js: " + checks + " checks passed");
