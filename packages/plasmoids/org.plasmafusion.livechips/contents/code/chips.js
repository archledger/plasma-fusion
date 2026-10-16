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
    keepawake: "M4 9h12v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5zM16 10h1.5a2.5 2.5 0 0 1 0 5H16M8 3c0 1.5 1 1.5 1 3M12 3c0 1.5 1 1.5 1 3"
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
