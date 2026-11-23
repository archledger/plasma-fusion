// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, "../contents/code/formats.js"), "utf8")
    .replace(/^\.pragma library$/m, ""), context);

test("seconds are opt-in and preserve the region's AM/PM order", () => {
    assert.equal(context.timeFormat("h:mm AP", 1, "en_US"), "h:mm AP");
    assert.equal(context.timeFormat("h:mm AP", 1, "en_US", true), "h:mm:ss AP");
    assert.equal(context.timeFormat("APh:mm", 1, "zh_TW", true), "APh:mm:ss");
});
test("seconds keep the region's separator", () => {
    assert.equal(context.timeFormat("H.mm", 1, "fi_FI", true), "H.mm.ss");
    assert.equal(context.timeFormat("HH.mm", 1, "da_DK", true), "HH.mm.ss");
    assert.match(context.timeFormat("H.mm", 0, "fi_FI", true), /mm\.ss/);
});
test("seconds respect forced hour cycle and quoted locale text", () => {
    assert.equal(context.timeFormat("h:mm AP", 2, "en_US", true), "HH:mm:ss");
    assert.equal(context.timeFormat("HH:mm", 0, "ko_KR", true), "AP h:mm:ss");
    assert.equal(context.timeFormat("HH 'h' mm", 1, "fr_CA", true), "HH 'h' mm:ss");
});
test("the width budget's short date is the region's short date without the year", () => {
    // Regions' short formats as Qt has them, and what step 4 of the width budget shows: the day and
    // the month in the region's order and with its separators, without the year and what joined
    // it to them. A dot right after the day or the month stays.
    const cases = {
        "M/d/yy": "M/d", // en_US
        "dd/MM/yyyy": "dd/MM", // en_GB, fr_FR
        "d/M/yy": "d/M", // es_ES
        "yyyy/MM/dd": "MM/dd", // ja_JP
        "d\u200f/M\u200f/yyyy": "d\u200f/M", // ar_EG: the mark before the year goes with it
        "yyyy-MM-dd": "MM-dd", // sv_SE
        "dd.MM.yy": "dd.MM.", // de_DE
        "yy. M. d.": "M. d.", // ko_KR
        "yyyy. MM. dd.": "MM. dd.", // hu_HU
        "d. M. yyyy": "d. M.", // sk_SK: the space before a final year goes with it
        "dd. MM. yyyy.": "dd. MM.", // hr_HR
        "d.M.yy.": "d.M.", // bs_BA: so does what follows a final year
        "d.MM.yy\u202f'\u0433'.": "d.MM.", // bg_BG: and the year's quoted suffix
        "d MM yyyy": "d MM", // C
    };
    const wrong = Object.entries(cases).filter(([format, wanted]) => context.numericDateFormat(format) !== wanted)
        .map(([format]) => format + " -> " + context.numericDateFormat(format));
    assert.deepEqual(wrong, []);
});
