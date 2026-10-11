// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/previews.js (not installed). Run: node tests/previews.test.js
// A fake ListModel records what the sync does: a title or active-window change must only set roles
// (the card and its thumbnail stream stay), never remove and insert the same window.
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "previews.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { syncCards } = globalThis;
assert.strictEqual(typeof syncCards, "function", "previews.js does not define syncCards");

// QML's ListModel, the calls syncCards uses; each row carries an id that stands for its delegate.
class FakeListModel {
    constructor() { this.rows = []; this.ops = []; this.nextId = 1; }
    get count() { return this.rows.length; }
    get(i) { return this.rows[i]; }
    setProperty(i, role, value) { this.rows[i][role] = value; this.ops.push(`set ${role}`); }
    insert(i, row) { this.rows.splice(i, 0, Object.assign({ delegate: this.nextId++ }, row)); this.ops.push("insert"); }
    move(from, to, n) { const moved = this.rows.splice(from, n); this.rows.splice(to, 0, ...moved); this.ops.push("move"); }
    remove(i, n) { this.rows.splice(i, n); this.ops.push("remove"); }
}
const win = (winId, title, extra) => Object.assign({ child: 0, title, winId, active: false, minimized: false }, extra);
const plain = (m) => m.rows.map(({ delegate, ...r }) => r);
const delegates = (m) => m.rows.map((r) => r.delegate);

// First show: one card per window.
let m = new FakeListModel();
let wanted = [win("a", "Konsole 1", { child: 0, active: true }), win("b", "Konsole 2", { child: 1 })];
syncCards(m, wanted);
assert.deepStrictEqual(plain(m), wanted, "cards for both windows");
const first = delegates(m);

// A title changes (a terminal prints a new prompt): only that role is set.
m.ops = [];
wanted = [win("a", "Konsole 1: ls", { child: 0, active: true }), win("b", "Konsole 2", { child: 1 })];
syncCards(m, wanted);
assert.deepStrictEqual(m.ops, ["set title"], "a title change sets the title only");
assert.deepStrictEqual(delegates(m), first, "both cards stay (their streams keep running)");
assert.deepStrictEqual(plain(m), wanted);

// The other window becomes active.
m.ops = [];
wanted = [win("a", "Konsole 1: ls", { child: 0 }), win("b", "Konsole 2", { child: 1, active: true })];
syncCards(m, wanted);
assert.deepStrictEqual(m.ops.sort(), ["set active", "set active"], "the active window moves by roles only");
assert.deepStrictEqual(delegates(m), first, "both cards stay");

// Nothing changed (a change elsewhere in the task model): no call at all.
m.ops = [];
syncCards(m, wanted);
assert.deepStrictEqual(m.ops, [], "an unrelated change touches no card");

// A window is minimized: its card stays, its stream request is cleared through the role.
m.ops = [];
wanted = [win("a", "Konsole 1: ls", { child: 0, minimized: true }), win("b", "Konsole 2", { child: 1, active: true })];
syncCards(m, wanted);
assert.deepStrictEqual(m.ops, ["set minimized"]);

// A window opens in between, one closes, the order changes.
m.ops = [];
wanted = [win("b", "Konsole 2", { child: 0, active: true }), win("c", "Konsole 3", { child: 1 })];
syncCards(m, wanted);
assert.deepStrictEqual(plain(m), wanted, "closed window gone, new one added, order kept");
assert.strictEqual(m.rows[0].delegate, first[1], "the window that stayed keeps its card");
assert.ok(!m.ops.includes("remove") || m.ops.filter((o) => o === "remove").length === 1, "one removal");

// The preview empties.
syncCards(m, []);
assert.strictEqual(m.count, 0, "no cards");
console.log("previews: all checks passed");
