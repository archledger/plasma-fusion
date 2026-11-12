// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Plasma Fusion dynamic tiling: the node tests for Tiling.js.
// Run with: node packages/kwin/tests/tiling.test.js

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "scripts", "plasmafusion-placement", "contents", "ui", "Tiling.js");
vm.runInThisContext(fs.readFileSync(file, "utf8").replace(/^.pragma library$/m, (l) => " ".repeat(l.length)), { filename: pathToFileURL(file).href });
const Tiling = globalThis;

// ---------------------------------------------------------------- the layout

exports.test_master_fraction_clamped = function(test) {
    test.equal(Tiling.masterFraction({masterFraction: 0.5}), 0.5);
    test.equal(Tiling.masterFraction({masterFraction: 0.1}), 0.25, "below the floor");
    test.equal(Tiling.masterFraction({masterFraction: 0.9}), 0.75, "above the ceiling");
    test.done();
};

exports.test_master_tile_rect = function(test) {
    const r = Tiling.masterTileRect(0.5);
    test.equal(r.x, 0);
    test.equal(r.y, 0);
    test.equal(r.width, 0.5);
    test.equal(r.height, 1);
    test.done();
};

exports.test_stack_rects_endpoint_rounded = function(test) {
    const area = { x: 0, y: 0, width: 1000, height: 901 };
    const rects = Tiling.stackRects(area, 500, 8, 3);
    test.equal(rects.length, 3);
    // The cells fill the column (endpoint-rounded, last flush).
    test.equal(rects[0].y, 0);
    test.equal(rects[2].y + rects[2].height, 901);
    // Each cell is at least 1px.
    for (const r of rects) {
        test.ok(r.height >= 1, "cell height >= 1");
        test.ok(r.width >= 1, "cell width >= 1");
    }
    test.done();
};

exports.test_stack_rects_zero_count = function(test) {
    test.equal(Tiling.stackRects({x:0,y:0,width:100,height:100}, 50, 8, 0).length, 0);
    test.done();
};

exports.test_stack_rects_single = function(test) {
    const area = { x: 0, y: 0, width: 1000, height: 800 };
    const rects = Tiling.stackRects(area, 500, 8, 1);
    test.equal(rects.length, 1);
    test.equal(rects[0].y, 0);
    test.equal(rects[0].height, 800);
    test.done();
};

// ---------------------------------------------------------------- feasibility

exports.test_feasible_in_cell = function(test) {
    test.ok(Tiling.feasibleInCell({width: 100, height: 50}, {width: 200, height: 100}));
    test.ok(!Tiling.feasibleInCell({width: 300, height: 50}, {width: 200, height: 100}));
    test.ok(!Tiling.feasibleInCell({width: 100, height: 150}, {width: 200, height: 100}));
    test.done();
};

// ---------------------------------------------------------------- the session

exports.test_create_session = function(test) {
    const s = Tiling.createSession();
    test.equal(s.active, false);
    test.equal(s.generation, 0);
    test.equal(s.master, null);
    test.equal(s.stack.length, 0);
    test.done();
};

exports.test_eligible_for_master = function(test) {
    test.ok(Tiling.eligibleForMaster({
        deleted: false, normalWindow: true, transient: false, modal: false,
        moveable: true, resizeable: true, fullScreen: false, tile: null,
        minimized: false, maximizeMode: 0
    }));
    test.ok(!Tiling.eligibleForMaster({
        deleted: false, normalWindow: true, transient: false, modal: false,
        moveable: true, resizeable: true, fullScreen: true, tile: null,
        minimized: false, maximizeMode: 0
    }), "fullscreen refused");
    test.ok(!Tiling.eligibleForMaster({
        deleted: false, normalWindow: true, transient: false, modal: false,
        moveable: true, resizeable: true, fullScreen: false, tile: {some: "tile"},
        minimized: false, maximizeMode: 0
    }), "tiled refused");
    test.done();
};

// ---------------------------------------------------------------- the focus cycle

exports.test_focus_order = function(test) {
    const session = { master: "M", stack: ["S1", "S2"] };
    const order = Tiling.focusOrder(session);
    test.deepEqual(order, ["M", "S1", "S2"]);
    test.done();
};

exports.test_next_in_cycle = function(test) {
    const session = { master: "M", stack: ["S1", "S2"] };
    test.equal(Tiling.nextInCycle(session, "M"), "S1");
    test.equal(Tiling.nextInCycle(session, "S1"), "S2");
    test.equal(Tiling.nextInCycle(session, "S2"), "M", "wraps to master");
    test.done();
};

exports.test_previous_in_cycle = function(test) {
    const session = { master: "M", stack: ["S1", "S2"] };
    test.equal(Tiling.previousInCycle(session, "M"), "S2", "wraps to last");
    test.equal(Tiling.previousInCycle(session, "S1"), "M");
    test.done();
};

// ---------------------------------------------------------------- the untoggle

exports.test_save_floats = function(test) {
    const floats = Tiling.saveFloats([
        { internalId: "a", frameGeometry: { x: 10, y: 20, width: 100, height: 50 } },
        { internalId: "b", frameGeometry: { x: 30, y: 40, width: 200, height: 100 } },
    ]);
    test.equal(floats.a.x, 10);
    test.equal(floats.a.width, 100);
    test.equal(floats.b.y, 40);
    test.done();
};

// ---------------------------------------------------------------- layout stack

exports.test_layout_stack_separates_infeasible = function(test) {
    const candidates = [
        { minSize: { width: 100, height: 50 } },
        { minSize: { width: 5000, height: 50 } },  // too wide
        { minSize: { width: 100, height: 50 } },
    ];
    const area = { x: 0, y: 0, width: 1000, height: 800 };
    const result = Tiling.layoutStack(candidates, area, 500, 8);
    test.equal(result.placed.length, 2, "two feasible");
    test.equal(result.floated.length, 1, "one floated");
    // The placed cells fill the column between just the feasible two.
    test.equal(result.placed[0].rect.height + result.placed[1].rect.height + 8, 800,
               "two cells + gap = area height (approx)");
    test.done();
};
console.log("tiling.test.js: all passed");
