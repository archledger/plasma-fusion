// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of contents/code/devices.js (not installed). Run: node tests/devices.test.js
// The engine data below is shaped as plasma5support 6.7.5's hotplug, soliddevice and
// devicenotifications engines publish it.
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "contents", "code", "devices.js");
const code = fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (line) => " ".repeat(line.length));
vm.runInThisContext(code, { filename: pathToFileURL(file).href });
const entries = globalThis.entries;
const used = globalThis.used;
assert.notStrictEqual(entries, undefined, "devices.js does not define entries");

const usb = "/org/freedesktop/UDisks2/block_devices/sdb1";
const internal = "/org/freedesktop/UDisks2/block_devices/nvme0n1p3";
const camera = "/org/kde/solid/udev/sys/devices/usb1/1-2";
const disc = "/org/freedesktop/UDisks2/block_devices/sr0";
const hotplug = {
    [usb]: { udi: usb, text: "USB STICK", icon: "drive-removable-media-usb", emblems: [],
             predicateFiles: ["gwenview_importer.desktop", "openWithFileManager.desktop"], isEncryptedContainer: false },
    [internal]: { udi: internal, text: "Data", icon: "drive-harddisk", predicateFiles: ["openWithFileManager.desktop"] },
    [camera]: { udi: camera, text: "Canon camera", icon: "camera-photo", predicateFiles: ["solid_camera.desktop"] },
    [disc]: { udi: disc, text: "Audio CD", icon: "media-optical-audio", predicateFiles: ["solid_audiocd.desktop"] }
};
const solid = {
    [usb]: { "Device Types": ["Storage Access", "Block", "Storage Volume"], Removable: true, Hotpluggable: true,
             Accessible: true, "File Path": "/run/media/pf/STICK", "Free Space": 3e9, Size: 8e9,
             "Free Space Text": "2.8 GiB", "Size Text": "7.5 GiB", State: 0, "Operation result": 1 },
    [internal]: { "Device Types": ["Storage Access", "Block", "Storage Volume"], Removable: false,
                  Hotpluggable: false, Accessible: true, State: 0 },
    [camera]: { "Device Types": ["Camera"], Removable: true, Hotpluggable: true, State: 0 },
    [disc]: { "Device Types": ["OpticalDisc", "Storage Volume", "Block"], Removable: true, Hotpluggable: true,
              State: 2, "Operation result": 0 }
};

// Removable and hot-pluggable devices only (the stock default filter), newest first.
let list = entries([internal, usb, camera, disc], hotplug, solid, {});
assert.deepStrictEqual(list.map(e => e.udi), [disc, camera, usb], "internal volume left out, newest first");

// A mounted stick: its path, sizes, use and the file manager action.
const stick = list[2];
assert.strictEqual(stick.name, "USB STICK");
assert.strictEqual(stick.mountable, true);
assert.strictEqual(stick.mounted, true);
assert.strictEqual(stick.path, "/run/media/pf/STICK");
assert.strictEqual(stick.freeText, "2.8 GiB");
assert.strictEqual(stick.openPredicate, "openWithFileManager.desktop", "the file manager action is preferred");
assert.ok(Math.abs(used(stick) - 0.625) < 1e-9, "5 of 8 GB in use");

// A camera: not mountable, opened with its own action.
const cam = list[1];
assert.strictEqual(cam.mountable, false);
assert.strictEqual(cam.mounted, false);
assert.strictEqual(cam.openPredicate, "solid_camera.desktop");
assert.strictEqual(used(cam), -1, "no sizes without a mounted volume");

// An optical disc being ejected: busy, recognised as a disc.
assert.strictEqual(list[0].optical, true);
assert.strictEqual(list[0].busy, true);

// Not yet described by soliddevice: left out until both engines know it.
assert.deepStrictEqual(entries([usb], hotplug, {}, {}), [], "no soliddevice data, not listed");

// The devicenotifications engine's messages: an error and the "safely removed" note.
const busy = { [usb + " notification"]: { solidError: 4, error: "One or more files on this device are open within an application.", udi: usb } };
list = entries([usb], hotplug, Object.assign({}, solid, { [usb]: Object.assign({}, solid[usb], { "Operation result": 2 }) }), busy);
assert.strictEqual(list[0].failed, true);
assert.strictEqual(list[0].messageIsError, true);
assert.match(list[0].message, /open within an application/);
const done = { [usb + " notification"]: { solidError: 0, error: "This device can now be safely removed.", udi: usb } };
list = entries([usb], hotplug, Object.assign({}, solid, { [usb]: Object.assign({}, solid[usb], { Accessible: false }) }), done);
assert.strictEqual(list[0].mounted, false);
assert.strictEqual(list[0].messageIsError, false, "safely removed is not an error");
assert.strictEqual(used(list[0]), -1, "an unmounted volume has no use figure");

console.log("devices: all checks passed");
