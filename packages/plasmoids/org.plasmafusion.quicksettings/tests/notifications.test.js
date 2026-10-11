// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/notifications.js (not installed). Run: node tests/notifications.test.js
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "notifications.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const { splitBody, sideImage, replyMode, jobState, fileActions, summaryShown, groupFooter } = globalThis;

// The body: declaration and wrapper gone, images taken out of the text and kept in order.
const server = '<?xml version="1.0"?><html>Look <img src="file:///tmp/a.png" alt="a"/> here<br/>'
             + "<img src='file:///tmp/b%20c.jpg'></img><img alt=\"denied\"/></html>";
assert.deepStrictEqual(splitBody(server), { text: "Look  here", images: ["file:///tmp/a.png", "file:///tmp/b%20c.jpg"] },
                       "images out of the text, in order, denied ones dropped, trailing break trimmed");
assert.deepStrictEqual(splitBody("<html>one\ntwo</html>\n"), { text: "one<br>two", images: [] }, "line ends become breaks, trimmed");
assert.deepStrictEqual(splitBody(undefined), { text: "", images: [] }, "no body");
assert.deepStrictEqual(splitBody('<img src="file:///x?a=1&amp;b=2"/>').images, ["file:///x?a=1&b=2"], "entities in the source");
assert.strictEqual(splitBody('<b>bold</b> <a href="https://kde.org">link</a>').text, '<b>bold</b> <a href="https://kde.org">link</a>',
                   "other markup kept");

// The image beside the text.
const image = { width: 64 };
assert.strictEqual(sideImage(image, "dialog-information", "konsole"), image, "the image first");
assert.strictEqual(sideImage(undefined, "dialog-information", "konsole"), "dialog-information", "else the notification's icon");
assert.strictEqual(sideImage(undefined, "konsole", "konsole"), null, "not the app icon twice");
assert.strictEqual(sideImage(undefined, "", "konsole"), null, "nothing");

// Inline reply.
assert.strictEqual(replyMode(false, 2), "none", "no reply action");
assert.strictEqual(replyMode(true, 0), "field", "reply only: the field at once");
assert.strictEqual(replyMode(true, 1), "button", "reply among others: a Reply button");
// Jobs.
assert.strictEqual(jobState(1, 0, 0), "", "a notification is not a job");
assert.strictEqual(jobState(2, 1, 0), "running", "running");
assert.strictEqual(jobState(2, 2, 0), "paused", "suspended");
assert.strictEqual(jobState(2, 0, 0), "finished", "stopped without error");
assert.strictEqual(jobState(2, 0, 14), "failed", "stopped with an error");

const none = { open: false, folder: false, folderUrl: "", highlight: false };
assert.deepStrictEqual(fileActions("running", 1, ""), none, "running: no file actions");
assert.deepStrictEqual(fileActions("failed", 1, "file:///home/u/a.txt"), none, "failed: no file actions");
assert.deepStrictEqual(fileActions("finished", 1, ""), none, "finished in the trash (no destination): none");
assert.deepStrictEqual(fileActions("finished", 1, "file:///home/u/a.txt"),
                       { open: true, folder: true, folderUrl: "file:///home/u/a.txt", highlight: true },
                       "one file: Open, and the folder with the file selected");
assert.deepStrictEqual(fileActions("finished", 3, "file:///home/u/dest"),
                       { open: false, folder: true, folderUrl: "file:///home/u/dest", highlight: false },
                       "several files: the destination folder");

// The summary line.
assert.strictEqual(summaryShown("Konsole ", "konsole"), false, "summary that repeats the app name");
assert.strictEqual(summaryShown("Build done", "Konsole"), true, "a real summary");
assert.strictEqual(summaryShown("", "Konsole"), false, "no summary");
// The group footer.
assert.deepStrictEqual(groupFooter(true, true, 5, 2, false), { shown: true, more: 3 }, "collapsed: Show 3 more");
assert.deepStrictEqual(groupFooter(true, true, 5, 5, true), { shown: true, more: 0 }, "expanded: Show fewer");
assert.deepStrictEqual(groupFooter(true, true, 2, 2, false), { shown: false, more: 0 }, "all shown, not expanded: nothing");
assert.deepStrictEqual(groupFooter(true, false, 5, 2, false).shown, false, "only under the last card");
assert.deepStrictEqual(groupFooter(false, true, 0, 0, false).shown, false, "not in a group");
console.log("notifications: all checks passed");
