// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// Pure logic of the window placement memory: plain objects in, plain objects out, no KWin types,
// so the node suite (packages/kwin/tests/placement.test.js) drives every rule. main.qml owns the
// KWin objects and the memory file.

// The identity a window is remembered under: the app's desktop file when it has one (its stable
// name), else the window class. Lowercased, so `konsole` and `org.kde.konsole` compare.
function appId(resourceClass, desktopFileName) {
    let id = String(desktopFileName || "");
    if (id !== "") {
        const slash = id.lastIndexOf("/");
        if (slash >= 0) {
            id = id.slice(slash + 1);
        }
        id = id.replace(/\.desktop$/, "");
    } else {
        id = String(resourceClass || "");
    }
    return id.toLowerCase();
}

// The names IgnoreApps is matched against: the app id and, when it differs, the window class - the
// setting promises both forms, and an X11 app's class (`LibreOffice`) often differs from its desktop
// file (`libreoffice-writer`).
function identities(resourceClass, desktopFileName) {
    const id = appId(resourceClass, desktopFileName);
    const windowClass = appId(resourceClass, "");
    return windowClass !== "" && windowClass !== id ? [id, windowClass] : [id];
}

// A rectangle the memory may hold: four finite numbers at a sane size. Returns the rounded copy,
// or null (a record with a broken value is dropped rather than trusted).
function valid(rect) {
    if (!rect || typeof rect !== "object") {
        return null;
    }
    const x = Number(rect.x);
    const y = Number(rect.y);
    const width = Number(rect.width);
    const height = Number(rect.height);
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(width) || !Number.isFinite(height)) {
        return null;
    }
    if (width < 50 || height < 50 || width > 20000 || height > 20000) {
        return null;
    }
    return { x: Math.round(x), y: Math.round(y), width: Math.round(width), height: Math.round(height) };
}

// The memory file's text -> app id -> rectangle. Anything unreadable is an empty memory.
function parse(text) {
    const apps = {};
    if (typeof text !== "string" || text === "") {
        return apps;
    }
    let data = null;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return apps;
    }
    if (!data || typeof data !== "object" || !data.apps || typeof data.apps !== "object") {
        return apps;
    }
    for (const id in data.apps) {
        const rect = valid(data.apps[id]);
        if (rect) {
            apps[id] = rect;
        }
    }
    return apps;
}

function serialize(apps) {
    return JSON.stringify({ v: 1, apps: apps });
}

// Whether the window floats on the desktop (the states in which the memory is recorded): not
// maximized in any way (full, vertical-only or horizontal-only - mode 0 means restore), not full
// screen and not tiled. state: {fullScreen, tiled, minimized, maximizeMode, ...}.
function floating(state) {
    return !state.fullScreen && !state.tiled && !state.minimized && state.maximizeMode === 0;
}

// The windows the memory touches at all: ordinary app windows that float; dialogs, transient and
// modal windows keep their own placement (KWin places them against their parent). A window KWin
// holds in place (`movable` false: a window rule that forces its position, or moving switched off)
// is left to KWin - the script's geometry write would bypass the rule.
function eligible(state) {
    return state.normal && !state.transient && !state.modal && state.movable !== false && floating(state);
}

// IgnoreApps: exact app id, or the entry as the last dot-separated part (`konsole` matches
// `org.kde.konsole`); case-insensitive. `ids` is one name or a window's identities.
function ignored(ids, list) {
    const names = Array.isArray(ids) ? ids : [ids];
    const entries = String(list || "").toLowerCase().split(",");
    for (let i = 0; i < entries.length; ++i) {
        const entry = entries[i].trim();
        if (entry === "") {
            continue;
        }
        for (let j = 0; j < names.length; ++j) {
            if (names[j] === entry || names[j].endsWith("." + entry)) {
                return true;
            }
        }
    }
    return false;
}

// The remembered rectangle's centre must lie on a screen the session has now; a spot on a monitor
// that is gone is left to KWin's placement.
function onScreen(rect, screens) {
    const cx = rect.x + rect.width / 2;
    const cy = rect.y + rect.height / 2;
    for (let i = 0; i < screens.length; ++i) {
        const s = screens[i];
        if (cx >= s.x && cx < s.x + s.width && cy >= s.y && cy < s.y + s.height) {
            return true;
        }
    }
    return false;
}

// Whether two windows are on a common desktop. The stack guard (and only the guard) is scoped to
// the desktop, so a window of the app that lives on another desktop does not keep a new one from
// the remembered spot. Plain views: {allDesktops, desktops} (desktop identities compared as is).
function sameDesktop(a, b) {
    if (a.allDesktops || b.allDesktops) {
        return true;
    }
    for (let i = 0; i < a.desktops.length; ++i) {
        if (b.desktops.indexOf(a.desktops[i]) >= 0) {
            return true;
        }
    }
    return false;
}

// The same for activities: views {activities}; KWin's list is empty when the window is on all
// activities, so an empty list on either side means "shared".
function sameActivity(a, b) {
    if (a.activities.length === 0 || b.activities.length === 0) {
        return true;
    }
    for (let i = 0; i < a.activities.length; ++i) {
        if (b.activities.indexOf(a.activities[i]) >= 0) {
            return true;
        }
    }
    return false;
}

// A window of the same app already sits (about) on the remembered spot on the same desktop:
// KWin's own placement takes the new window instead, which offsets it, instead of stacking it
// exactly.
function collides(rect, others, tolerance) {
    const t = tolerance === undefined ? 8 : tolerance;
    for (let i = 0; i < others.length; ++i) {
        if (Math.abs(others[i].x - rect.x) <= t && Math.abs(others[i].y - rect.y) <= t) {
            return true;
        }
    }
    return false;
}

// Whether the remembered size is given back: RememberSize on and a window that can be resized (a
// window rule that forces its size, or a fixed-size window, keeps the size it opened with).
function restoreSize(state, rememberSize) {
    return !!rememberSize && state.resizable !== false;
}

// The rectangle to give back: the remembered one, or its position with the size the window opened
// with (RememberSize off).
function restoreRect(saved, current, rememberSize) {
    if (rememberSize) {
        return { x: saved.x, y: saved.y, width: saved.width, height: saved.height };
    }
    return { x: saved.x, y: saved.y, width: current.width, height: current.height };
}

// The whole restore decision: the rectangle to apply, or null when the window keeps KWin's
// placement. `others` are the open windows of the same app on the same desktop and activity; a
// window without an identity (no desktop file, no class) is never restored or remembered.
function restoreFor(id, state, saved, screens, others, list, rememberSize, current) {
    if (id === "" || !eligible(state) || ignored(id, list) || !saved) {
        return null;
    }
    const rect = restoreRect(saved, current, restoreSize(state, rememberSize));
    if (!onScreen(rect, screens) || collides(rect, others)) {
        return null;
    }
    return rect;
}

function same(a, b) {
    return !!a && !!b && a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height;
}

// Remember rect for id; true when the memory changed (the caller then writes the file). A window
// without an identity is not remembered.
function remember(apps, id, rect) {
    if (id === "") {
        return false;
    }
    const clean = valid(rect);
    if (!clean || same(apps[id], clean)) {
        return false;
    }
    apps[id] = clean;
    return true;
}
