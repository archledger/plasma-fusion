// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the attached dialogs script, contents/code/main.js, run whole against a model of KWin's
// JavaScript scripting: a dialog placed under its parent's title bar, what the script does with a
// window KWin has destroyed, its alive() rule for a window reference, and a check that no file of
// the script reads deleted outside alive() (#184; the snap, placement and tablet scripts' rule,
// #181 and #182).
// Run: node packages/kwin/tests/attach.test.js (80-kwin.sh runs it).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const dir = path.join(__dirname, "..", "scripts", "plasmafusion-attach", "contents", "code");
const file = path.join(dir, "main.js");
const source = fs.readFileSync(file, "utf8");

// A signal: handlers connected and disconnected by identity; disconnecting one that is not
// connected throws, as Qt's disconnect does.
function signal() {
    const handlers = [];
    return {
        connect(fn) {
            handlers.push(fn);
        },
        disconnect(fn) {
            const i = handlers.indexOf(fn);
            if (i < 0) {
                throw new Error("disconnect: the function is not connected");
            }
            handlers.splice(i, 1);
        },
        emit(...args) {
            for (const fn of handlers.slice()) {
                fn(...args);
            }
        },
        get connected() {
            return handlers.length;
        },
    };
}

// A window: `ref` is what the script holds, `state` its properties. KWin marks a closing window
// deleted and destroys it a moment later. After destroy(), every property of the reference reads
// undefined (deleted too), and a write fails: Qt's QObjectWrapper::virtualPut returns false for a
// deleted object and strict code (the script's "use strict") turns that into a TypeError
// (qtdeclarative 6.11.2, qv4qobjectwrapper.cpp and qv4runtime.cpp, SetLookupStrict); a Proxy whose
// set trap answers false does the same here.
function window(props) {
    const state = Object.assign({
        deleted: false, modal: false, dialog: false, transient: false, transientFor: null,
        moveable: true, fullScreen: false, desktopWindow: false, dock: false, noBorder: false,
        move: false, resize: false,
        frameGeometry: { x: 0, y: 0, width: 100, height: 100 },
        clientGeometry: { x: 0, y: 0, width: 100, height: 100 },
        frameGeometryChanged: signal(), interactiveMoveResizeStarted: signal(),
        interactiveMoveResizeFinished: signal(), closed: signal(), modalChanged: signal(),
        transientChanged: signal(),
    }, props);
    let destroyed = false;
    const ref = new Proxy(state, {
        get: (target, key) => (destroyed ? undefined : target[key]),
        set: (target, key, value) => {
            if (destroyed) {
                return false;
            }
            target[key] = value;
            return true;
        },
    });
    return { ref, state, destroy() { destroyed = true; } };
}

// A rectangle as a plain object of this realm: the script's own objects come from the script's
// context, whose Object.prototype deepStrictEqual would compare.
const rect = (r) => ({ x: r.x, y: r.y, width: r.width, height: r.height });

// A parent window with a 30 px title bar at 100,100 800x600, and a modal dialog for it.
function parentWindow() {
    return window({
        frameGeometry: { x: 100, y: 100, width: 800, height: 600 },
        clientGeometry: { x: 100, y: 130, width: 800, height: 570 },
    });
}
function dialogFor(parent) {
    return window({
        dialog: true, modal: true, transient: true, transientFor: parent.ref,
        frameGeometry: { x: 0, y: 0, width: 300, height: 200 },
        clientGeometry: { x: 0, y: 0, width: 300, height: 200 },
    });
}

// The script loaded in a fresh model of KWin's scripting: readConfig, workspace and KWin.
function load(settings) {
    const workspace = {
        windowAdded: signal(),
        windowRemoved: signal(),
        windowList: () => [],
        clientArea: () => ({ x: 0, y: 0, width: 1920, height: 1080 }),
    };
    const context = vm.createContext({
        readConfig: (key, fallback) => (settings && key in settings ? settings[key] : fallback),
        workspace,
        KWin: { MaximizeArea: 2 },
    });
    vm.runInContext(source, context, { filename: pathToFileURL(file).href });
    // The script's top-level const Maps and functions, as the script sees them.
    const read = (name) => vm.runInContext(name, context);
    return { workspace, read };
}

// A modal dialog is placed centred on its parent, its top on the title bar's bottom.
{
    const script = load();
    const parent = parentWindow(), dialog = dialogFor(parent);
    script.workspace.windowAdded.emit(dialog.ref);
    assert.deepStrictEqual(rect(dialog.state.frameGeometry),
                           { x: 350, y: 130, width: 300, height: 200 });
    assert.ok(script.read("attached").has(dialog.ref));
    assert.strictEqual(parent.state.frameGeometryChanged.connected, 1,
                       "the dialog follows its parent");
}

// The parent destroyed while the dialog is attached, then the dialog changes its own size: the
// dialog is let go. The guard used to pass (the destroyed parent's deleted reads undefined) and
// place() read the parent's undefined frame: a TypeError out of the dialog's geometry handler.
{
    const script = load();
    const parent = parentWindow(), dialog = dialogFor(parent);
    script.workspace.windowAdded.emit(dialog.ref);
    parent.destroy();
    dialog.state.frameGeometry = { x: 350, y: 130, width: 320, height: 210 };
    assert.doesNotThrow(() => dialog.state.frameGeometryChanged.emit(), "a destroyed parent");
    assert.deepStrictEqual(rect(dialog.state.frameGeometry),
                           { x: 350, y: 130, width: 320, height: 210 },
                           "not placed from a destroyed parent's geometry");
    assert.ok(!script.read("attached").has(dialog.ref), "the dialog is detached");
    assert.strictEqual(script.read("children").size, 0, "nothing kept for the parent");
    assert.strictEqual(dialog.state.frameGeometryChanged.connected, 0,
                       "the dialog's handlers are gone");
    assert.strictEqual(dialog.state.closed.connected, 0);
}

// A dialog whose title bar the script hid (HideDialogTitleBar) destroyed before its parent closes.
// Nothing is written to it, and the rest of detach() still runs: the parent's entry and handler go.
// The guard used to pass, and the write to the destroyed dialog threw in the middle of detach().
{
    const script = load({ HideDialogTitleBar: true });
    const parent = parentWindow(), dialog = dialogFor(parent);
    script.workspace.windowAdded.emit(dialog.ref);
    assert.strictEqual(dialog.state.noBorder, true, "the script hid the dialog's title bar");
    dialog.destroy();
    parent.state.deleted = true; // closing: KWin marks it deleted before windowRemoved
    assert.doesNotThrow(() => script.workspace.windowRemoved.emit(parent.ref),
                        "a destroyed dialog");
    assert.strictEqual(dialog.state.noBorder, true, "nothing written to a destroyed window");
    assert.ok(!script.read("attached").has(dialog.ref));
    assert.ok(!script.read("children").has(parent.ref), "the parent's entry is gone");
    assert.strictEqual(parent.state.frameGeometryChanged.connected, 0, "and its handler");
}

// The same with a dialog that is only closing: its title bar is not given back either (it is
// going).
{
    const script = load({ HideDialogTitleBar: true });
    const parent = parentWindow(), dialog = dialogFor(parent);
    script.workspace.windowAdded.emit(dialog.ref);
    dialog.state.deleted = true;
    dialog.state.closed.emit();
    assert.strictEqual(dialog.state.noBorder, true);
    assert.ok(!script.read("attached").has(dialog.ref));
    assert.strictEqual(parent.state.frameGeometryChanged.connected, 0);
}

// ...and a dialog detached alive (dragged away) gets its title bar back.
{
    const script = load({ HideDialogTitleBar: true });
    const parent = parentWindow(), dialog = dialogFor(parent);
    script.workspace.windowAdded.emit(dialog.ref);
    dialog.state.interactiveMoveResizeStarted.emit();
    dialog.state.interactiveMoveResizeFinished.emit();
    assert.strictEqual(dialog.state.noBorder, false, "DetachOnMove: the title bar back");
    assert.ok(!script.read("attached").has(dialog.ref));
}

// eligible() takes neither a destroyed dialog nor one whose parent reference was destroyed (the
// destroyed parent used to pass its checks and titleBarHeight() read its undefined geometry).
{
    const script = load();
    const eligible = script.read("eligible");
    const parent = parentWindow(), dialog = dialogFor(parent);
    assert.strictEqual(eligible(dialog.ref), true);
    parent.destroy();
    assert.doesNotThrow(() => assert.strictEqual(eligible(dialog.ref), false),
                        "a destroyed parent");
    const other = dialogFor(parentWindow());
    other.destroy();
    assert.strictEqual(eligible(other.ref), false, "a destroyed dialog");
    const closingParent = parentWindow();
    closingParent.state.deleted = true;
    assert.strictEqual(eligible(dialogFor(closingParent).ref), false, "a closing parent");
}

// alive(): only a window whose deleted is the boolean false is live. A closing window has deleted
// true; a reference to a destroyed window is a truthy object whose every property reads undefined,
// so "not deleted" is true of it.
{
    const alive = load().read("alive");
    assert.strictEqual(typeof alive, "function", "main.js defines alive()");
    const open = window(), closing = window({ deleted: true }), gone = window();
    gone.destroy();
    assert.strictEqual(alive(open.ref), true, "an open window");
    assert.strictEqual(alive(closing.ref), false, "a closing window");
    assert.strictEqual(alive(gone.ref), false, "a destroyed window: every property undefined");
    assert.strictEqual(alive(null), false);
    assert.strictEqual(alive(undefined), false);
}

// Every read of a window's deleted in the script goes through alive(); comments aside, alive()
// itself is the one place that reads it.
{
    const blank = (text) => text.replace(/[^\n]/g, " ");
    const reads = [];
    for (const name of fs.readdirSync(dir).filter((n) => /\.js$/.test(n)).sort()) {
        const text = fs.readFileSync(path.join(dir, name), "utf8")
            .replace(/\/\*[\s\S]*?\*\//g, blank)
            .replace(/function alive\(\w*\) \{[^}]*\}/, blank);
        text.split("\n").forEach((line, i) => {
            if (/\.deleted\b/.test(line.replace(/\/\/.*$/, ""))) {
                reads.push(name + ":" + (i + 1));
            }
        });
    }
    assert.deepStrictEqual(reads, [], "a window's deleted read outside alive()");
}

console.log("attach.test.js: ok");
