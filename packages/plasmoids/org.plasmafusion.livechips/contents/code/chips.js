// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Live chips (LiveChips board): what the chips show, from what the sources report. No QML here,
// so tests/chips.test.js runs it in node.
.pragma library

// The privacy kinds in the capsule, left to right: the most serious first.
var PRIVACY_ORDER = ["remote", "screen", "camera", "microphone", "ssh"];

// The board's glyphs (24-unit line paths, stroke 1.8).
var GLYPHS = {
    microphone: "M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3zM5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21",
    camera: "M3 7h11a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1zM15 10.5l6-3.5v10l-6-3.5",
    screen: "M3 4h18a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zM8 21h8M12 17v4M9 10.5l3-3 3 3M12 7.5v6",
    remote: "M5 3l12 6.5-5.5 1.5L9 16.5zM12 11l5 5",
    ssh: "M3 5h18a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zM6.5 10l3 2.5-3 2.5M12 15.5h5",
    keepawake: "M4 9h12v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5zM16 10h1.5a2.5 2.5 0 0 1 0 5H16M8 3c0 1.5 1 1.5 1 3M12 3c0 1.5 1 1.5 1 3",
    // Plasma's notices in the island (the Island board's "volume, brightness and Plasma's notices")
    speaker: "M4 9.5h3.5L12 5.5v13l-4.5-4H4zM15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11",
    speakerOff: "M4 9.5h3.5L12 5.5v13l-4.5-4H4zM16 9.5l5 5M21 9.5l-5 5",
    microphoneOff: "M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3zM5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21M4 4l16 16",
    sun: "M12 8.4a3.6 3.6 0 1 0 0 7.2a3.6 3.6 0 1 0 0-7.2zM12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4",
    keyboardLight: "M3 12h18v7H3zM7 15.5h10M12 3v3M6 5l1.5 2M18 5l-1.5 2"
};

// The badge tints of the Colors board, behind a capsule of one kind and behind each panel row's
// glyph (the glyphs themselves take the colour scheme's ForegroundNeutral, -Positive, -Visited,
// -Negative and -Link).
var TINTS = {
    dark: {
        microphone: [242, 166, 90, 0.20], camera: [58, 166, 91, 0.22], screen: [155, 123, 240, 0.22],
        remote: [217, 67, 75, 0.24], recording: [217, 67, 75, 0.24], ssh: [91, 157, 255, 0.20]
    },
    light: {
        microphone: [242, 166, 90, 0.24], camera: [58, 166, 91, 0.20], screen: [155, 123, 240, 0.20],
        remote: [217, 67, 75, 0.16], recording: [217, 67, 75, 0.16], ssh: [91, 157, 255, 0.18]
    }
};

function tint(kind, dark) {
    var t = TINTS[dark ? "dark" : "light"][kind];
    return t ? { r: t[0] / 255, g: t[1] / 255, b: t[2] / 255, a: t[3] } : null;
}

// The privacy capsule for the kinds in use (an object of kind -> true): its glyphs in order, and
// the kind whose tint it takes (one kind only; several share a neutral capsule).
function capsule(active) {
    var kinds = [];
    for (var i = 0; i < PRIVACY_ORDER.length; ++i) {
        if (active[PRIVACY_ORDER[i]]) {
            kinds.push(PRIVACY_ORDER[i]);
        }
    }
    return { kinds: kinds, tintKind: kinds.length === 1 ? kinds[0] : "" };
}

// The %1 of a translated message whose pattern is known: the pattern is the same message with a
// marker in place of %1 (from the sending app's own catalogue, so any language works). Empty
// when the text does not have the pattern's shape.
function argument(text, pattern, marker) {
    text = String(text || "");
    pattern = String(pattern || "");
    var at = pattern.indexOf(marker);
    if (at < 0) {
        return "";
    }
    var prefix = pattern.slice(0, at);
    var suffix = pattern.slice(at + marker.length);
    if (text.length < prefix.length + suffix.length || text.slice(0, prefix.length) !== prefix
            || text.slice(text.length - suffix.length) !== suffix) {
        return "";
    }
    return text.slice(prefix.length, text.length - suffix.length);
}

// xdg-desktop-portal-kde's two status items share their id; the icon tells them apart
// (screencast.cpp media-record, remotedesktop.cpp krfb).
function portalKind(iconName) {
    if (iconName === "krfb") {
        return "remote";
    }
    if (iconName === "media-record") {
        return "screen";
    }
    return "";
}

// systemd-logind sessions (Manager.ListSessions and each Session's properties) to the ones the
// chip shows: remote ones (sshd, Tailscale SSH) that are not closing, oldest first. Each entry:
// { id, user, remote, remoteHost, service, state, since (microseconds) }.
function remoteLogins(sessions) {
    var out = [];
    for (var i = 0; i < sessions.length; ++i) {
        var s = sessions[i];
        if (!s || !s.remote || s.state === "closing") {
            continue;
        }
        out.push({
            id: String(s.id),
            user: String(s.user || ""),
            host: String(s.remoteHost || ""),
            ssh: s.service === "sshd" || s.service === "tailscaled",
            since: Number(s.since || 0) / 1000
        });
    }
    out.sort(function (a, b) { return a.since - b.since || (a.id < b.id ? -1 : 1); });
    return out;
}

// The apps reading a camera, from `pw-dump` (an array of PipeWire objects): the application name
// of every video stream linked from a camera node (a Video/Source with media.role Camera, as
// kpipewire's camera monitor counts them, or a libcamera/v4l2 device node). Unique, in order.
function cameraApps(objects) {
    if (!Array.isArray(objects)) {
        return [];
    }
    var nodes = {};
    var links = [];
    for (var i = 0; i < objects.length; ++i) {
        var o = objects[i];
        if (!o || !o.info) {
            continue;
        }
        if (o.type === "PipeWire:Interface:Node") {
            nodes[o.id] = o.info.props || {};
        } else if (o.type === "PipeWire:Interface:Link") {
            links.push(o.info);
        }
    }
    function isCamera(props) {
        if (!props || props["media.class"] !== "Video/Source") {
            return false;
        }
        var api = String(props["device.api"] || "");
        return props["media.role"] === "Camera" || api === "libcamera" || api === "v4l2";
    }
    var names = [];
    for (var l = 0; l < links.length; ++l) {
        var from = nodes[links[l]["output-node-id"]];
        var to = nodes[links[l]["input-node-id"]];
        if (!isCamera(from) || !to || String(to["media.class"] || "").indexOf("Stream/Input/Video") !== 0) {
            continue;
        }
        var name = String(to["application.name"] || to["node.description"] || to["node.name"] || "");
        if (name.length > 0 && names.indexOf(name) < 0) {
            names.push(name);
        }
    }
    return names;
}

// The status items being read (StatusItems.qml): a read gets the token of the item's registration,
// and its reply is taken only while that token is current, so a reply that comes after the item
// unregistered (readForgotten) is dropped, also when the same name registers again. Replies to
// reads of one registration all count (D-Bus keeps their order).
function newReads() {
    return { serial: 0, live: {} };
}
function readStarted(reads, key) {
    if (!(key in reads.live)) {
        reads.serial += 1;
        reads.live[key] = reads.serial;
    }
    return reads.live[key];
}
function readForgotten(reads, key) {
    delete reads.live[key];
}
function readCurrent(reads, key, token) {
    return reads.live[key] === token;
}

// What the chips are, without the running time: the chips' places change only with it.
function layoutKey(capsuleKinds, recording, keepAwake) {
    return capsuleKinds.join(",") + "|" + (recording ? "recording" : "") + "|" + (keepAwake ? "keepawake" : "");
}

// Keep awake's time left as whole hours and minutes, the minutes rounded up (a timer with 30 s
// left says 1 min, not 0).
function timeLeft(endMs, nowMs) {
    var minutes = Math.max(0, Math.ceil((endMs - nowMs) / 60000));
    return { hours: Math.floor(minutes / 60), minutes: minutes % 60, total: minutes };
}

// ---- The island (board Island.dc.html): while the top bar is hidden, after Apple's Dynamic Island.

// The colours on the island: it is black in light and dark, so its glyphs and dots take the dark
// colour scheme's semantic colours (PlasmaFusionDark.colors [Colors:Window]: ForegroundPositive,
// -Neutral, -Visited, -Negative, -Link), the LiveChips board's dark ones.
var ISLAND_COLOURS = {
    camera: "#7fd99c", microphone: "#f5c08c", screen: "#c3a6ff", remote: "#ff8a8f", recording: "#ff8a8f", ssh: "#8ab8ff"
};

// Plasma's notices (plasmashell 6.7.5 shell/osd.cpp, its osdProgress and osdText signals): the
// glyph the board draws for Plasma's icon name, or "" (the island then shows Plasma's icon itself:
// a player's, or another notice's).
function noticeGlyph(icon) {
    var name = String(icon || "");
    if (name === "audio-volume-muted") {
        return "speakerOff";
    }
    if (name.indexOf("audio-volume-") === 0) {
        return "speaker";
    }
    if (name === "microphone-sensitivity-muted") {
        return "microphoneOff";
    }
    if (name.indexOf("microphone-sensitivity-") === 0) {
        return "microphone";
    }
    if (name === "video-display-brightness") {
        return "sun";
    }
    if (name === "input-keyboard-brightness") {
        return "keyboardLight";
    }
    return "";
}

// The level's colours on the island: white to 100 %, then Plasma's own steps (osd.cpp: warning to
// 125 %, danger past it), in the island's microphone and recording colours.
var NOTICE_COLOURS = { plain: "#ffffff", warning: "#f5c08c", danger: "#ff8a8f" };

// A notice as the island shows it: from osdProgress(ICON, PERCENT, MAXIMUM, TEXT) a level, from
// osdText(ICON, TEXT) (PERCENT null) a text. { glyph, icon, level: bool, value: "60", fill: 0..1
// of the bar, tick: where 100 % is on the bar when the maximum is above it (else -1), tone: "plain" |
// "warning" | "danger", text: one line (Plasma's lines joined with " · ") }.
function notice(icon, percent, maximum, text) {
    var level = percent !== null && percent !== undefined;
    var p = level ? Math.max(0, Number(percent) || 0) : 0;
    var max = level ? Math.max(1, Number(maximum) || 100) : 100;
    return {
        glyph: noticeGlyph(icon),
        icon: String(icon || ""),
        level: level,
        value: level ? String(Math.round(p)) : "",
        fill: level ? Math.min(p, max) / max : 0,
        tick: level && max > 100 ? 100 / max : -1,
        tone: !level || p <= 100 ? "plain" : p <= 125 ? "warning" : "danger",
        text: String(text || "").split("\n").map(function (line) { return line.trim(); })
            .filter(function (line) { return line.length > 0; }).join(" · ")
    };
}

// What the island shows, from what is going on: S { privacy: [kinds] (capsule().kinds),
// recording, keepAwake, music (playing): bools, musicOpened: the music's view is open, musicPlayer:
// a player is still there (paused in its open view the music stays, so Play is there; a player
// that quit takes it along), fullScreen: the active window of the screen is full screen }.
// The privacy kinds always come first, then a screen recording, a Keep awake timer and the music
// playing: the first two of them show (the first in the island, the second in a bubble beside
// it). In a full-screen window only the privacy kinds show, as dots. { mode: "none" | "compact" |
// "dots", items: [names], dots: [privacy kinds] }. A notice of Plasma's (S.notice, notice())
// takes the island while it shows, also over a full-screen window: { mode: "compact", items:
// ["notice"], dots, notice }.
function island(s) {
    var privacy = s.privacy || [];
    if (s.notice) {
        return { mode: "compact", items: ["notice"], dots: privacy.slice(), notice: s.notice };
    }
    if (s.fullScreen) {
        return privacy.length > 0 ? { mode: "dots", items: [], dots: privacy.slice() } : { mode: "none", items: [], dots: [] };
    }
    var items = [];
    if (privacy.length > 0) {
        items.push("privacy");
    }
    if (s.recording) {
        items.push("recording");
    }
    if (s.keepAwake) {
        items.push("keepawake");
    }
    if (s.music || (s.musicOpened && s.musicPlayer)) {
        items.push("music");
    }
    items = items.slice(0, 2);
    return { mode: items.length > 0 ? "compact" : "none", items: items, dots: privacy.slice() };
}

// The opened island's rows: one for each app (by name, whatever it uses) and each remote login,
// the most serious first, each with its kinds in the capsule's order and the action that ends
// the most serious of them: End (remote control), Stop sharing (the screen), Mute or Unmute (the
// microphone: an app's streams together, Mute while any of them records). MICROPHONE_APPS
// [{ name, muted }], CAMERA_APPS [names] (else CAMERA_NAMES while a camera is in use), PORTAL
// [{ key, kind, app }], LOGINS [{ id, user, host }].
// [{ app, kinds, action: "end" | "stop" | "mute" | "unmute" | "", microphones: [indexes], session: key, login }]
function islandRows(microphoneApps, cameraApps, cameraInUse, cameraNames, portal, logins) {
    var rows = [];
    function row(name) {
        var key = String(name || "").toLowerCase();
        for (var i = 0; i < rows.length; ++i) {
            if (rows[i].login === "" && rows[i].app.toLowerCase() === key) {
                return rows[i];
            }
        }
        var r = { app: String(name || ""), kinds: [], action: "", microphones: [], session: "", login: "" };
        rows.push(r);
        return r;
    }
    function add(r, kind) {
        if (r.kinds.indexOf(kind) < 0) {
            r.kinds.push(kind);
            r.kinds.sort(function (a, b) { return PRIVACY_ORDER.indexOf(a) - PRIVACY_ORDER.indexOf(b); });
        }
    }
    for (var m = 0; m < microphoneApps.length; ++m) {
        var mic = row(microphoneApps[m].name);
        add(mic, "microphone");
        mic.microphones.push(m);
        if (mic.action === "" || mic.action === "unmute") {
            mic.action = microphoneApps[m].muted ? "unmute" : "mute";
        }
    }
    if (cameraInUse) {
        var named = cameraApps.length > 0 ? cameraApps : cameraNames;
        for (var c = 0; c < named.length; ++c) {
            add(row(named[c]), "camera");
        }
        if (named.length === 0) {
            add(row(""), "camera");
        }
    }
    for (var p = 0; p < portal.length; ++p) {
        var s = portal[p];
        if (s.kind !== "screen" && s.kind !== "remote") {
            continue;
        }
        var r = row(s.app);
        add(r, s.kind);
        if (s.kind === "remote" || r.action !== "end") {
            r.action = s.kind === "remote" ? "end" : "stop";
            r.session = String(s.key);
        }
    }
    for (var l = 0; l < logins.length; ++l) {
        rows.push({ app: logins[l].host !== "" ? logins[l].user + "@" + logins[l].host : logins[l].user, kinds: ["ssh"], action: "",
                    microphones: [], session: "", login: String(logins[l].id) });
    }
    rows.sort(function (a, b) { return PRIVACY_ORDER.indexOf(a.kinds[0]) - PRIVACY_ORDER.indexOf(b.kinds[0]); });
    return rows;
}

// An icon name to try for an app known by its name ("Firefox" -> "firefox", "Google Chrome" ->
// "google-chrome"); the island shows the kind's glyph when the theme has no such icon.
function iconGuess(name) {
    return String(name || "").trim().toLowerCase().replace(/\s+/g, "-");
}

// Whether a screen is taken by a full-screen window, from its WINDOWS [{ fullScreen, minimized }],
// the last activated first: the first one not minimized is full screen. Not the globally active
// window: with another screen's window focused, the full-screen one still covers its screen.
function fullScreenOf(windows) {
    for (var i = 0; i < windows.length; ++i) {
        if (!windows[i].minimized) {
            return windows[i].fullScreen === true;
        }
    }
    return false;
}
