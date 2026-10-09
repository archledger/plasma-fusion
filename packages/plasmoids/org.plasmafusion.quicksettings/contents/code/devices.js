.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Disks & Devices (quick settings): the devices Fusion lists from Plasma's hotplug, soliddevice and
    devicenotifications data engines (plasma5support, as Plasma 5's Disks & Devices used them). Like
    the stock widget's default filter (plasma-workspace 6.7.5 storageinfo.cpp): a device whose drive
    is removable or hot-pluggable, a camera or a media player. Newest first.
    Tests: tests/devices.test.js (not installed).
*/

// soliddevice "State" and "Operation result" (plasma5support soliddeviceengine.h). Its "Device Types"
// are untranslated names: "Storage Access", "OpticalDisc", "Camera", "Portable Media Player".
var IDLE = 0;
var MOUNTING = 1;
var UNMOUNTING = 2;
var UNSUCCESSFUL = 2;

// The file manager action every mountable volume has (solid/actions/openWithFileManager.desktop).
var OPEN_PREDICATE = "openWithFileManager.desktop";

function removable(solid) {
    const types = solid["Device Types"] || [];
    return solid.Removable === true || solid.Hotpluggable === true
        || types.indexOf("Camera") !== -1 || types.indexOf("Portable Media Player") !== -1;
}

// One entry per listed device. hotplug, solid and notes map a source name to its data:
// hotplug and solid are keyed by UDI, notes by "<UDI> notification" (devicenotifications engine).
// order lists UDIs in the order they were added (oldest first).
function entries(order, hotplug, solid, notes) {
    const out = [];
    for (let i = order.length - 1; i >= 0; --i) {
        const udi = order[i];
        const hp = hotplug[udi];
        const sd = solid[udi];
        if (!hp || !sd || !removable(sd)) {
            continue;
        }
        const types = sd["Device Types"] || [];
        const mountable = types.indexOf("Storage Access") !== -1;
        const note = notes[udi + " notification"] || null;
        const predicates = hp.predicateFiles || [];
        out.push({
            udi: udi,
            name: hp.text || sd.Description || sd.Label || udi,
            icon: hp.icon || sd.Icon || "drive-removable-media",
            emblems: hp.emblems || sd.Emblems || [],
            mountable: mountable,
            optical: types.indexOf("OpticalDisc") !== -1,
            mounted: mountable && sd.Accessible === true,
            path: sd["File Path"] || "",
            free: typeof sd["Free Space"] === "number" ? sd["Free Space"] : -1,
            size: typeof sd.Size === "number" ? sd.Size : -1,
            freeText: sd["Free Space Text"] || "",
            sizeText: sd["Size Text"] || "",
            busy: sd.State === MOUNTING || sd.State === UNMOUNTING,
            state: sd.State || IDLE,
            failed: sd["Operation result"] === UNSUCCESSFUL,
            // the engine's own message: an error (with the blocking applications) or "can now be
            // safely removed" (solidError 0)
            message: note ? (note.error || "") : "",
            messageIsError: note ? note.solidError !== 0 : false,
            openPredicate: predicates.indexOf(OPEN_PREDICATE) !== -1 ? OPEN_PREDICATE : (predicates[0] || ""),
            encrypted: hp.isEncryptedContainer === true
        });
    }
    return out;
}

// Fraction of the device in use (0..1), or -1 when the sizes are not known (not mounted).
function used(entry) {
    if (!entry.mounted || entry.size <= 0 || entry.free < 0) {
        return -1;
    }
    return Math.min(1, Math.max(0, (entry.size - entry.free) / entry.size));
}
