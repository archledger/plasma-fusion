// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/jobs.js (not installed). Run: node tests/jobs.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "jobs.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { progressByApp, withJobs } = globalThis;
assert.strictEqual(typeof progressByApp, "function", "jobs.js does not define progressByApp");
assert.strictEqual(typeof withJobs, "function", "jobs.js does not define withJobs");

const RUNNING = 1, SUSPENDED = 2, STOPPED = 0;
const job = (desktopEntry, percentage, state) => ({ desktopEntry, percentage, state: state ?? RUNNING });

// One copy in Dolphin at 37 %: Dolphin's tile shows 0.37.
assert.deepStrictEqual(progressByApp([job("org.kde.dolphin", 37)]), { "org.kde.dolphin": { count: 1, progress: 0.37 } });
// Two of an app's jobs: their mean, in whole percent (stock: integer division), suspended ones count.
assert.deepStrictEqual(progressByApp([job("org.kde.dolphin", 10), job("org.kde.dolphin", 25, SUSPENDED)]),
                       { "org.kde.dolphin": { count: 2, progress: 0.17 } }, "mean of two jobs, floored");
// Stopped (finished or failed) jobs and jobs without an app are left out; a desktop file name works too.
assert.deepStrictEqual(progressByApp([job("org.kde.dolphin", 100, STOPPED), job("", 50), job("firefox.desktop", 80)]),
                       { firefox: { count: 1, progress: 0.8 } }, "stopped and anonymous jobs ignored");
assert.deepStrictEqual(progressByApp([job("org.kde.ark", 140), job("org.kde.ark", -3)]), { "org.kde.ark": { count: 2, progress: 0.5 } },
                       "percentages clamped to 0..100");
assert.deepStrictEqual(progressByApp([job("org.kde.ark", undefined)]), { "org.kde.ark": { count: 1, progress: 0 } }, "no percentage yet");
assert.deepStrictEqual(progressByApp([]), {}, "no jobs");
assert.deepStrictEqual(progressByApp(undefined), {}, "no model yet");

// Merged with the apps' own (Unity) state: the app's own progress wins, its count stays.
const unity = { "org.telegram.desktop": { count: 4, countVisible: true, progress: 0, progressVisible: false, urgent: false },
                "org.kde.discover": { count: 0, countVisible: false, progress: 0.9, progressVisible: true, urgent: false } };
const merged = withJobs(unity, { "org.telegram.desktop": { count: 1, progress: 0.4 }, "org.kde.discover": { count: 1, progress: 0.1 },
                                 "org.kde.dolphin": { count: 1, progress: 0.37 } });
assert.deepStrictEqual(merged["org.telegram.desktop"], { count: 4, countVisible: true, progress: 0.4, progressVisible: true, urgent: false },
                       "job progress next to the app's own count");
assert.strictEqual(merged["org.kde.discover"].progress, 0.9, "the app's own progress wins");
assert.deepStrictEqual(merged["org.kde.dolphin"], { count: 0, countVisible: false, urgent: false, progress: 0.37, progressVisible: true },
                       "an app with only a job");
assert.strictEqual(unity["org.telegram.desktop"].progressVisible, false, "the input is not changed");
assert.deepStrictEqual(withJobs(unity, {}), unity, "no jobs: the entries as they are");
assert.deepStrictEqual(withJobs(undefined, undefined), {}, "nothing at all");
console.log("jobs: ok");
