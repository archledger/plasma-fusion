// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Test tooling (not installed): runs a desktop script the way plasmashell's evaluateScript does,
// against a small model of the scripting API (panels() with id, screen, location, lengthMode,
// floating, height and hiding; screenCount; gridUnit; ConfigFile().readEntry; print()). Used by
// panel-scripts-unit.sh.
//
//   node scripting_model.js LAYOUT_JSON SCRIPT
//
// LAYOUT_JSON: {screens, font, panels: [{id, screen, location, lengthMode, floating, height}]};
// changed heights are written back to it. A panel on a screen that is not there behaves as in
// Plasma 6.8: reading or writing its length mode, floating, height or hiding crashes the shell
// (the model prints "crashed" on stderr and exits 139 without an answer), as plasmashell crashes
// on the invalid config group of a missing screen.
"use strict";
const fs = require("fs");
const vm = require("vm");

const [layoutFile, script] = process.argv.slice(2);
const layout = JSON.parse(fs.readFileSync(layoutFile, "utf8"));
const screens = layout.screens;
const printed = [];

function view(panel, what) {
    // Plasma 6.7 puts such a panel on screen -1 and reads the first screen's config instead.
    if (Math.max(panel.screen, 0) >= screens) {
        process.stderr.write("crashed: the " + what + " of panel " + panel.id + " on missing screen " + panel.screen + "\n");
        process.exit(139);
    }
}

function panelObject(panel) {
    const o = { get id() { return panel.id; }, get screen() { return panel.screen; }, get location() { return panel.location; } };
    for (const key of ["lengthMode", "floating", "height", "hiding"]) {
        Object.defineProperty(o, key, {
            get() { view(panel, key); return panel[key]; },
            set(value) { view(panel, key); panel[key] = value; },
        });
    }
    return o;
}

const context = vm.createContext({
    panels: () => layout.panels.map(panelObject),
    screenCount: screens,
    gridUnit: 18,
    ConfigFile: () => ({ readEntry: () => layout.font || "" }),
    print: (text) => printed.push(String(text)),
});
vm.runInContext(script, context);
fs.writeFileSync(layoutFile, JSON.stringify(layout));
process.stdout.write(printed.join("\n") + "\n");
