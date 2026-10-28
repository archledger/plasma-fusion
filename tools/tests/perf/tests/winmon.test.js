// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

test("winmon records typed, JSON-safe identity without changing legacy events", () => {
    const messages = [];
    let added, removed;
    const context = {
        workspace: {
            windowList: () => [],
            windowAdded: { connect: callback => { added = callback; } },
            windowRemoved: { connect: callback => { removed = callback; } },
        },
        print: () => {},
        callDBus: (...args) => messages.push(args.at(-1)),
        Date: { now: () => 12345 },
    };
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../winmon.js"), "utf8"), context);
    const window = { resourceClass: "org.kde.plasmashell", resourceName: "plasmashell",
        caption: 'a|b "quoted"\nnext', internalId: "{card}", windowType: 18,
        appletPopup: true, width: 680, height: 700, dock: false };
    added(window);
    removed(window);
    const records = messages.filter(line => line.startsWith("PFPERF window "))
        .map(line => JSON.parse(line.slice("PFPERF window ".length)));
    assert.equal(records.length, 2);
    assert.deepEqual(records[0], { schema: 1, event: "added", time_ms: 12345, id: "{card}",
        resourceClass: "org.kde.plasmashell", caption: window.caption, windowType: 18,
        appletPopup: true, width: 680, height: 700 });
    assert.equal(records[1].event, "removed");
    assert(messages.some(line => line.startsWith("PFPERF added 12345 ")));
    assert(messages.some(line => line.startsWith("PFPERF removed 12345 ")));
    assert(messages.some(line => line.includes("winmon loaded 12345 geometry")));
});
