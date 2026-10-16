// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the snap script's contents/ui/Gestures.js (touchpad gestures you can set) and of the
// handlers main.qml has for them.
// Run: node packages/kwin/tests/gestures.test.js (80-kwin.sh runs it).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const dir = path.join(__dirname, "..", "scripts", "plasmafusion-snap", "contents", "ui");
const file = path.join(dir, "Gestures.js");
vm.runInThisContext(fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (l) => " ".repeat(l.length)), { filename: pathToFileURL(file).href });
const { GESTURES, ACTIONS, actionFor, kwinShortcut, quickSettingsMode, quickSettingsScript, desktopSwitching } = globalThis;

let n = 0;
function test(name, f) {
    f();
    n++;
    console.log("ok " + n + " " + name);
}

test("the gestures and their defaults (the owner's choice, 2026-10-16)", () => {
    assert.deepStrictEqual(GESTURES.map((g) => [g.key, g.fallback]), [
        ["GestureSwipeUp3", "overview"], ["GestureSwipeDown3", "desktop"], ["GestureSwipeLeft3", "none"],
        ["GestureSwipeRight3", "none"], ["GesturePinchIn4", "launcher"], ["GesturePinchOut4", "desktop"]]);
});
test("the actions, in the settings page's order", () => {
    assert.deepStrictEqual(ACTIONS, ["none", "overview", "desktop", "grid", "windows", "launcher", "quicksettings", "notifications", "snaplayouts"]);
});
test("a setting names its action; empty or unknown is the gesture's default", () => {
    assert.strictEqual(actionFor("GestureSwipeLeft3", "windows"), "windows");
    assert.strictEqual(actionFor("GestureSwipeUp3", " Grid "), "grid", "case and spaces do not matter");
    assert.strictEqual(actionFor("GestureSwipeUp3", ""), "overview");
    assert.strictEqual(actionFor("GestureSwipeDown3", undefined), "desktop");
    assert.strictEqual(actionFor("GesturePinchIn4", "teleport"), "launcher", "a later version's action");
    assert.strictEqual(actionFor("GestureSwipeUp3", "none"), "none", "Nothing is a choice, not a fallback");
    assert.strictEqual(actionFor("NoSuchGesture", ""), "none");
});
test("KWin's shortcuts (kwin 6.7.5 overvieweffect.cpp, windowvieweffect.cpp) and quick settings' modes", () => {
    assert.deepStrictEqual(["overview", "grid", "windows", "desktop", "launcher"].map(kwinShortcut), ["Overview", "Grid View", "Expose", "", ""]);
    assert.deepStrictEqual(["quicksettings", "notifications", "overview"].map(quickSettingsMode), ["toggle", "notifications", ""]);
});
test("the openRequest script writes '<mode>:<nonce>' to every quick settings widget", () => {
    const writes = [];
    const widget = { set currentConfigGroup(g) { this.group = g; }, writeConfig(k, v) { writes.push([this.group.join("/"), k, v]); } };
    const panels = () => [{ widgets: (type) => (type === "org.plasmafusion.quicksettings" ? [widget, widget] : []) }];
    new Function("panels", quickSettingsScript("toggle", 42))(panels);
    assert.deepStrictEqual(writes, [["General", "openRequest", "toggle:42"], ["General", "openRequest", "toggle:42"]]);
});
test("KWin's desktop switch (its slide or fade) is seen in its active effects, a list or its text", () => {
    assert.strictEqual(desktopSwitching(["blur", "slide"]), true);
    assert.strictEqual(desktopSwitching("blur,fadedesktop"), true);
    assert.strictEqual(desktopSwitching(["blur", "overview"]), false, "not every effect");
    assert.strictEqual(desktopSwitching("slideback,blur"), false, "a whole name only");
    assert.strictEqual(desktopSwitching(""), false);
    assert.strictEqual(desktopSwitching(undefined), false);
});
test("main.qml has KWin's shortcuts wait for a desktop switch, and invokes them after it", () => {
    const qml = fs.readFileSync(path.join(dir, "main.qml"), "utf8");
    const run = qml.slice(qml.indexOf("function runGesture("), qml.indexOf("SwipeGestureHandler {"));
    assert.match(run, /if \(shortcut !== ""\) \{[^}]*desktopSwitchCall\.call\(\);/);
    assert.doesNotMatch(run, /kwinShortcutCall\.call/, "not at once");
    const check = qml.slice(qml.indexOf("id: desktopSwitchCall"), qml.indexOf("id: desktopSwitchTimer"));
    assert.match(check, /Gestures\.desktopSwitching\(active\)[^{]*\{[^}]*desktopSwitchTimer\.restart\(\);\s*return;/);
    assert.match(check, /root\.invokePendingShortcut\(\);/);
});
test("main.qml listens to each gesture with its direction and finger count, and runs its key", () => {
    const qml = fs.readFileSync(path.join(dir, "main.qml"), "utf8");
    const found = [];
    const re = /(SwipeGestureHandler|PinchGestureHandler) \{\s*direction: \w+\.Direction\.(\w+)\s*fingerCount: (\d)[\s\S]*?onActivated: root\.runGesture\("(\w+)"\)/g;
    let m;
    while ((m = re.exec(qml)) !== null) {
        found.push([m[4], m[1] === "PinchGestureHandler" ? "pinch" : "swipe", m[2], Number(m[3])]);
    }
    const want = { up: "Up", down: "Down", left: "Left", right: "Right", in: "Contracting", out: "Expanding" };
    assert.deepStrictEqual(found, GESTURES.map((g) => [g.key, g.kind, want[g.direction], g.fingers]));
});
console.log("all " + n + " passed");
