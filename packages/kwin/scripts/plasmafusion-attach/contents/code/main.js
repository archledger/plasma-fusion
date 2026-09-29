/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Plasma Fusion attached dialogs (Windows board, "Dialogs · Attached to the parent window").
//
// A modal dialog is placed horizontally centred on its parent window and just under the
// parent's title bar, and it follows the parent when the parent moves or changes size.
// Dragging the dialog yourself detaches it (setting DetachOnMove). Parents without a title bar
// drawn by KWin (client-side decorations) keep KWin's own dialog placement.
//
// Settings: kwinrc [Script-plasmafusion-attach] FollowParent, DetachOnMove, TitleBarGap,
// HideDialogTitleBar (see contents/config/main.xml).

"use strict";

function setting(key, fallback) {
    const value = readConfig(key, fallback);
    if (typeof fallback === "boolean") {
        return value === true || value === "true";
    }
    if (typeof fallback === "number") {
        const n = Number(value);
        return isNaN(n) ? fallback : n;
    }
    return value;
}

const followParent = setting("FollowParent", true);
const detachOnMove = setting("DetachOnMove", true);
const titleBarGap = Math.max(0, Math.min(64, setting("TitleBarGap", 0)));
const hideDialogTitleBar = setting("HideDialogTitleBar", false);

// dialog -> { parent, placing, handlers }
const attached = new Map();
// parent -> set of dialogs
const children = new Map();
// every window we watch for modal/transient changes -> handlers
const watched = new Map();

function titleBarHeight(win) {
    return Math.max(0, win.clientGeometry.y - win.frameGeometry.y);
}

function eligible(dialog) {
    if (!dialog || dialog.deleted || !dialog.modal || !dialog.moveable || dialog.fullScreen) {
        return false;
    }
    const parent = dialog.transientFor;
    if (!parent || parent.deleted || parent.desktopWindow || parent.dock || parent.fullScreen) {
        return false;
    }
    return titleBarHeight(parent) > 0;
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

function place(dialog) {
    const entry = attached.get(dialog);
    if (!entry) {
        return;
    }
    const parent = entry.parent;
    if (parent.deleted || dialog.deleted) {
        detach(dialog);
        return;
    }
    const p = parent.frameGeometry;
    const d = dialog.frameGeometry;
    const area = workspace.clientArea(KWin.MaximizeArea, parent);
    const x = Math.round(clamp(p.x + (p.width - d.width) / 2, area.x, area.x + area.width - d.width));
    const y = Math.round(clamp(p.y + titleBarHeight(parent) + titleBarGap, area.y, area.y + area.height - d.height));
    if (Math.abs(d.x - x) < 1 && Math.abs(d.y - y) < 1) {
        return;
    }
    entry.placing = true;
    dialog.frameGeometry = { x: x, y: y, width: d.width, height: d.height };
    entry.placing = false;
}

function placeChildren(parent) {
    const set = children.get(parent);
    if (!set) {
        return;
    }
    for (const dialog of Array.from(set)) {
        const entry = attached.get(dialog);
        if (entry && !entry.userMoving) {
            place(dialog);
        }
    }
}

function attach(dialog) {
    if (attached.has(dialog) || !eligible(dialog)) {
        return;
    }
    const parent = dialog.transientFor;
    const entry = { parent: parent, placing: false, userMoving: false, hidTitleBar: false, handlers: [] };
    attached.set(dialog, entry);
    if (!children.has(parent)) {
        const set = new Set();
        children.set(parent, set);
        const onParentGeometry = () => {
            if (followParent) {
                placeChildren(parent);
            }
        };
        set.onParentGeometry = onParentGeometry;
        parent.frameGeometryChanged.connect(onParentGeometry);
    }
    children.get(parent).add(dialog);

    const onDialogGeometry = () => {
        // The dialog changed its own size: keep it centred under the title bar.
        if (!entry.placing && !entry.userMoving && !dialog.move && !dialog.resize) {
            place(dialog);
        }
    };
    const onMoveStarted = () => {
        entry.userMoving = true;
    };
    const onMoveFinished = () => {
        entry.userMoving = false;
        if (detachOnMove) {
            detach(dialog);
        } else {
            place(dialog);
        }
    };
    const onClosed = () => detach(dialog);
    dialog.frameGeometryChanged.connect(onDialogGeometry);
    dialog.interactiveMoveResizeStarted.connect(onMoveStarted);
    dialog.interactiveMoveResizeFinished.connect(onMoveFinished);
    dialog.closed.connect(onClosed);
    entry.handlers = [
        [dialog.frameGeometryChanged, onDialogGeometry],
        [dialog.interactiveMoveResizeStarted, onMoveStarted],
        [dialog.interactiveMoveResizeFinished, onMoveFinished],
        [dialog.closed, onClosed],
    ];
    if (hideDialogTitleBar && !dialog.noBorder) {
        dialog.noBorder = true;
        entry.hidTitleBar = true;
    }
    place(dialog);
}

function detach(dialog) {
    const entry = attached.get(dialog);
    if (!entry) {
        return;
    }
    attached.delete(dialog);
    for (const [signal, handler] of entry.handlers) {
        try {
            signal.disconnect(handler);
        } catch (e) {
            // the window is already gone
        }
    }
    if (entry.hidTitleBar && !dialog.deleted) {
        dialog.noBorder = false;
    }
    const set = children.get(entry.parent);
    if (set) {
        set.delete(dialog);
        if (set.size === 0) {
            try {
                entry.parent.frameGeometryChanged.disconnect(set.onParentGeometry);
            } catch (e) {
                // the parent is already gone
            }
            children.delete(entry.parent);
        }
    }
}

// Modal state and parents can be set after a window appears.
function reconsider(win) {
    if (eligible(win)) {
        attach(win);
    } else if (attached.has(win) && (!win.modal || win.transientFor !== attached.get(win).parent)) {
        detach(win);
        attach(win);
    }
}

function watch(win) {
    if (watched.has(win) || !win.dialog && !win.modal && !win.transient) {
        return;
    }
    const handler = () => reconsider(win);
    win.modalChanged.connect(handler);
    win.transientChanged.connect(handler);
    watched.set(win, handler);
    reconsider(win);
}

function unwatch(win) {
    detach(win);
    const handler = watched.get(win);
    if (handler) {
        watched.delete(win);
    }
    const set = children.get(win);
    if (set) {
        for (const dialog of Array.from(set)) {
            detach(dialog);
        }
    }
}

workspace.windowAdded.connect(watch);
workspace.windowRemoved.connect(unwatch);
for (const win of workspace.windowList()) {
    watch(win);
}
