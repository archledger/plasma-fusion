// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the dock's End Task in contents/code/endtask.js (not installed): the process ids it
// takes, the windows that get no End Task, and the command itself, run with sh against stand-in
// processes: one that quits on SIGTERM, one that ignores it (ended by SIGKILL after the wait) and
// one named plasmashell (left alone). Run: node tests/endtask.test.js
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { spawn, spawnSync } = require("child_process");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "endtask.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { endTaskPids, endTaskCommand, sessionApp } = globalThis;

assert.deepStrictEqual(endTaskPids([4321, "4321", 0, 1, -7, 3.5, "x", null, 99]), [4321, 99], "whole numbers above 1, once each");
assert.strictEqual(endTaskCommand([]), "", "no process: no command");
assert.strictEqual(endTaskCommand([0, 1, "x"]), "", "nothing valid: no command");
assert.ok(sessionApp("org.kde.plasmashell") && !sessionApp("org.kde.kwrite") && !sessionApp(""), "the shell's windows get no End Task");

// The command against real processes.
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pf-endtask-"));
const sleepBin = spawnSync("sh", ["-c", "command -v sleep"], { encoding: "utf8" }).stdout.trim();
fs.copyFileSync(sleepBin, path.join(tmp, "plasmashell"));
fs.chmodSync(path.join(tmp, "plasmashell"), 0o755);
const ended = (child) => new Promise((resolve) => child.on("exit", (codeValue, signal) => resolve(signal || codeValue)));
// A process's end, or "still running" after `ms` (so a red fails at once instead of hanging).
const within = (promise, ms) => Promise.race([promise, new Promise((resolve) => setTimeout(() => resolve("still running"), ms))]);
const polite = spawn(sleepBin, ["60"]);
const stubborn = spawn("sh", ["-c", "trap '' TERM; exec " + sleepBin + " 60"]);
const shell = spawn(path.join(tmp, "plasmashell"), ["60"]);
const politeEnd = ended(polite), stubbornEnd = ended(stubborn);
let shellGone = false;
shell.on("exit", () => { shellGone = true; });

process.on("unhandledRejection", (e) => {
    for (const c of [polite, stubborn, shell]) {
        try { c.kill("SIGKILL"); } catch (err) { /* gone */ }
    }
    console.error(String(e && e.stack || e));
    process.exit(1);
});
setTimeout(async () => {
    const start = Date.now();
    const run = spawnSync("sh", ["-c", endTaskCommand([polite.pid, stubborn.pid, shell.pid, 0])], { encoding: "utf8", timeout: 15000 });
    const took = Date.now() - start;
    assert.strictEqual(run.status, 0, "the command succeeds: " + run.stderr);
    assert.strictEqual(await within(politeEnd, 2000), "SIGTERM", "an app that answers SIGTERM quits on it");
    assert.strictEqual(await within(stubbornEnd, 2000), "SIGKILL", "one that ignores it gets SIGKILL");
    assert.ok(took >= 2500 && took < 8000, "SIGKILL only after the wait (" + took + " ms)");
    await new Promise((resolve) => setTimeout(resolve, 200));
    assert.ok(!shellGone, "a process named plasmashell is left alone");
    shell.kill("SIGKILL");
    // An app that quits at once: the command returns at once.
    const quick = spawn(sleepBin, ["60"]);
    const quickEnd = ended(quick);
    await new Promise((resolve) => setTimeout(resolve, 100));
    const t0 = Date.now();
    spawnSync("sh", ["-c", endTaskCommand([quick.pid])], { timeout: 15000 });
    assert.strictEqual(await within(quickEnd, 2000), "SIGTERM");
    assert.ok(Date.now() - t0 < 2000, "no wait once the app is gone (" + (Date.now() - t0) + " ms)");
    fs.rmSync(tmp, { recursive: true, force: true });
    console.log("endtask.test.js: all passed");
    process.exit(0);
}, 200);
