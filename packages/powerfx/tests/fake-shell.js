// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// A stand-in for plasmashell's desktop scripting (plasma-workspace 6.7.5 shell/scripting), enough
// for plasma-fusion-powerfx's widget script: desktops(), panels(), widgets(), id, type,
// currentConfigGroup, readConfig (converted to the default's type, as KConfigGroup::readEntry does)
// and writeConfig (stored as KConfig text). A layout is JSON:
//   {"desktops": [[WIDGET, ...], ...], "panels": [[WIDGET, ...], ...]}
//   WIDGET = {"id": 12, "type": "org.plasmafusion.dock", "config": {"General": {"magnify": "true"}}}
//
//   node fake-shell.js LAYOUT.json [WRITES.log] < SCRIPT   runs SCRIPT, saves the layout, prints
//                                                           the script's print() output
//   require("./fake-shell.js").run(script, layout, writes)  the same in-process
"use strict";

function convert(raw, def) {
    if (raw === undefined)
        return def;
    if (typeof def === "boolean")
        return /^(true|1|yes|on)$/i.test(raw);
    if (typeof def === "number") {
        const n = parseInt(raw, 10);
        return isNaN(n) ? def : n;
    }
    return raw;
}

function wrap(w, writes) {
    let group = [];
    return {
        get id() { return w.id; },
        get type() { return w.type; },
        get currentConfigGroup() { return group; },
        set currentConfigGroup(g) { group = g; },
        readConfig(key, def) {
            const g = w.config[group.join("][")] || {};
            return convert(g[key], def);
        },
        writeConfig(key, value) {
            const name = group.join("][");
            w.config[name] = w.config[name] || {};
            w.config[name][key] = String(value);
            writes.push(`${w.id} [${name}] ${key}=${String(value)}`);
        },
    };
}

function run(script, layout, writes) {
    let out = "";
    const containment = (ws) => ({ widgets: () => ws.map((w) => wrap(w, writes)) });
    const api = {
        desktops: () => (layout.desktops || []).map(containment),
        panels: () => (layout.panels || []).map(containment),
        print: (s) => { out += String(s); },
    };
    // eslint-disable-next-line no-new-func
    new Function("desktops", "panels", "print", script)(api.desktops, api.panels, api.print);
    return out;
}

module.exports = { run };

if (require.main === module) {
    const fs = require("fs");
    const layout = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    const writes = [];
    const script = fs.readFileSync(0, "utf8");
    const out = run(script, layout, writes);
    fs.writeFileSync(process.argv[2] + ".tmp", JSON.stringify(layout, null, 1));
    fs.renameSync(process.argv[2] + ".tmp", process.argv[2]);
    if (process.argv[3] && writes.length)
        fs.appendFileSync(process.argv[3], writes.join("\n") + "\n");
    process.stdout.write(out);
}
