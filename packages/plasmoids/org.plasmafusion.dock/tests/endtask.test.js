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
const { endTaskPids, endTaskCommand, identityCommand, identities, boundTo, sessionApp, stillOurs, START_TIME } = globalThis;

assert.deepStrictEqual(endTaskPids([4321, "4321", 0, 1, -7, 3.5, "x", null, 99]), [4321, 99], "whole numbers above 1, once each");
assert.strictEqual(endTaskCommand([]), "", "no process: no command");
assert.strictEqual(endTaskCommand(["0:5", "1:5", "x", "12"]), "", "nothing valid: no command");
assert.strictEqual(identityCommand([0, 1, "x"]), "", "no process to read: no command");
assert.deepStrictEqual(identities("4321:123\n1:9\nnoise\n4321:555\n 77:8 \n"), ["4321:123", "77:8"],
                       "identities: PID above 1, START, each PID once");
assert.deepStrictEqual(boundTo(["4321:123", "77:8"], [77, 99]), ["77:8"], "only those of processes still to end");
assert.deepStrictEqual(boundTo(["4321:123"], []), [], "none left");
assert.ok(sessionApp("org.kde.plasmashell") && !sessionApp("org.kde.kwrite") && !sessionApp(""), "the shell's windows get no End Task");
// At the confirmation's click: only processes the app had when asked and its windows still have.
assert.deepStrictEqual(stillOurs([4321, 4322, 4323], [4322, 4323, 4400]), [4322, 4323], "one quit meanwhile, a new one came: neither");
assert.deepStrictEqual(stillOurs([4321], []), [], "the app is gone: nothing to end (its number may be another process's now)");
assert.deepStrictEqual(stillOurs([4321, 0, "x"], [4321]), [4321], "still validated");

// The start time the command keeps for a process is its /proc/PID/stat field 22, also for a
// process whose name holds spaces and parentheses (the kernel's name, from its file name).
const oddDir = fs.mkdtempSync(path.join(os.tmpdir(), "pf-endtask-name-"));
const sleepPath = spawnSync("sh", ["-c", "command -v sleep"], { encoding: "utf8" }).stdout.trim();
fs.copyFileSync(sleepPath, path.join(oddDir, "a (b) c"));
fs.chmodSync(path.join(oddDir, "a (b) c"), 0o755);
const odd = spawn(path.join(oddDir, "a (b) c"), ["5"]);
const oddStat = fs.readFileSync("/proc/" + odd.pid + "/stat", "utf8");
assert.ok(oddStat.indexOf("(a (b) c)") > 0, "the process's name has spaces and parentheses: " + oddStat.slice(0, 40));
const oddStart = spawnSync("sh", ["-c", START_TIME + "st " + odd.pid], { encoding: "utf8" }).stdout.trim();
assert.strictEqual(oddStart, oddStat.slice(oddStat.lastIndexOf(")") + 2).split(" ")[19], "its start time, field 22");
assert.ok(/^[0-9]+$/.test(oddStart), "a number (" + oddStart + ")");
odd.kill("SIGKILL");
fs.rmSync(oddDir, { recursive: true, force: true });

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
// The identities the dock reads when it asks: "PID:START" for each, but not the session's own.
const idsOf = (pids) => identities(spawnSync("sh", ["-c", identityCommand(pids)], { encoding: "utf8", timeout: 5000 }).stdout);
const startOf = (pid) => spawnSync("sh", ["-c", START_TIME + "st " + pid], { encoding: "utf8" }).stdout.trim();
setTimeout(async () => {
    const read = idsOf([polite.pid, stubborn.pid, shell.pid, 0]);
    assert.deepStrictEqual(read, [polite.pid + ":" + startOf(polite.pid), stubborn.pid + ":" + startOf(stubborn.pid)],
                           "identities read: the two apps with their start times, not the process named plasmashell");
    // A process whose start time is not the one read (its number went to it later) gets nothing,
    // not even SIGTERM; nor does one named plasmashell, even with its true identity.
    const other = spawn(sleepBin, ["60"]);
    const otherEnd = ended(other);
    await new Promise((resolve) => setTimeout(resolve, 100));
    spawnSync("sh", ["-c", endTaskCommand([other.pid + ":1", shell.pid + ":" + startOf(shell.pid)])], { timeout: 15000 });
    assert.strictEqual(await within(otherEnd, 500), "still running", "a process that is not the one read gets no signal");
    assert.ok(!shellGone, "a process named plasmashell gets none either");
    other.kill("SIGKILL");
    const start = Date.now();
    const run = spawnSync("sh", ["-c", endTaskCommand(read)], { encoding: "utf8", timeout: 15000 });
    const took = Date.now() - start;
    assert.strictEqual(run.status, 0, "the command succeeds: " + run.stderr);
    assert.strictEqual(await within(politeEnd, 2000), "SIGTERM", "an app that answers SIGTERM quits on it");
    assert.strictEqual(await within(stubbornEnd, 2000), "SIGKILL", "one that ignores it gets SIGKILL");
    assert.ok(took >= 2500 && took < 8000, "SIGKILL only after the wait (" + took + " ms)");
    await new Promise((resolve) => setTimeout(resolve, 200));
    assert.ok(!shellGone, "a process named plasmashell is left alone");
    shell.kill("SIGKILL");
    // The wait over before the first look (the machine paused for longer than it): the one that
    // ignores SIGTERM still gets SIGKILL.
    const late = spawn("sh", ["-c", "trap '' TERM; exec " + sleepBin + " 60"]);
    const lateEnd = ended(late);
    await new Promise((resolve) => setTimeout(resolve, 200));
    const lateCommand = endTaskCommand(idsOf([late.pid]));
    assert.ok(lateCommand.indexOf("+ 300))") > 0, "the command waits 300 hundredths of a second");
    spawnSync("sh", ["-c", lateCommand.replace("+ 300))", "- 1))")], { timeout: 15000 });
    assert.strictEqual(await within(lateEnd, 2000), "SIGKILL", "a wait over before the first look still ends the app");
    // An app that quits at once: the command returns at once.
    const quick = spawn(sleepBin, ["60"]);
    const quickEnd = ended(quick);
    await new Promise((resolve) => setTimeout(resolve, 100));
    const t0 = Date.now();
    spawnSync("sh", ["-c", endTaskCommand(idsOf([quick.pid]))], { timeout: 15000 });
    assert.strictEqual(await within(quickEnd, 2000), "SIGTERM");
    assert.ok(Date.now() - t0 < 2000, "no wait once the app is gone (" + (Date.now() - t0) + " ms)");
    fs.rmSync(tmp, { recursive: true, force: true });
    console.log("endtask.test.js: all passed");
    process.exit(0);
}, 200);
