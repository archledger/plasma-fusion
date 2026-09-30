// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// The pen as KWin knows it (PEN.md 3.1): the first input device whose tabletTool is true, read once
// at start from org.kde.KWin /org/kde/KWin/InputDevice and again when a device is added or removed
// (a USB or Bluetooth pen tablet; the built-in digitizer never goes away). No polling. Without
// libinput (every virtual session) the object does not exist and the read fails: "no pen".
//
// Writes go through KWin's device properties, which KWin stores in kcminputrc itself:
// pressureCurve, outputName and mapToWorkspace (PEN.md 3.4).
Item {
    id: dev

    visible: false
    width: 0
    height: 0

    // Test sessions only (the widget's forcePen key): act as if a pen existed.
    property bool forcePen: false

    property string sysName: ""
    property string name: ""
    property string outputName: ""
    property bool mapToWorkspace: false
    property string pressureCurve: ""
    // USB-style ids, for the device's own kcminputrc group ([Libinput][vendor][product][name]).
    property int vendor: 0
    property int product: 0
    // True once KWin answered (with or without a pen).
    property bool known: false
    readonly property bool present: sysName.length > 0
    readonly property bool hasPen: present || forcePen

    // One line per write or failure, for the tests' journal checks.
    signal logged(string text)

    readonly property string service: "org.kde.KWin"
    readonly property string root: "/org/kde/KWin/InputDevice"
    readonly property string deviceIface: "org.kde.KWin.InputDevice"

    function properties(path: string, member: string, args, signature: string, resolve, reject): void {
        const message = {
            "service": dev.service,
            "path": path,
            "iface": "org.freedesktop.DBus.Properties",
            "member": member
        };
        if (args.length > 0) {
            message.arguments = args;
            message.signature = signature;
        }
        DBus.SessionBus.asyncCall(message, resolve, reject);
    }

    // Reads the device list, then each device until one is a tablet tool.
    function refresh(): void {
        properties(root, "Get", [new DBus.string("org.kde.KWin.InputDeviceManager"), new DBus.string("devicesSysNames")], "(ss)",
                   reply => {
                       const names = reply.value || [];
                       dev.probe(Array.from(names), 0);
                   }, () => {
                       dev.clear();
                       dev.known = true;
                   });
    }
    function probe(names, index: int): void {
        if (index >= names.length) {
            clear();
            known = true;
            return;
        }
        const path = root + "/" + names[index];
        properties(path, "GetAll", [new DBus.string(deviceIface)], "(s)", reply => {
            const p = reply.value || {};
            if (p.tabletTool === true) {
                dev.sysName = names[index];
                dev.name = String(p.name || "");
                dev.outputName = String(p.outputName || "");
                dev.mapToWorkspace = p.mapToWorkspace === true;
                dev.pressureCurve = String(p.pressureCurve || "");
                dev.vendor = Number(p.vendor || 0);
                dev.product = Number(p.product || 0);
                dev.known = true;
            } else {
                dev.probe(names, index + 1);
            }
        }, () => dev.probe(names, index + 1));
    }
    function clear(): void {
        sysName = "";
        name = "";
        outputName = "";
        mapToWorkspace = false;
        pressureCurve = "";
        vendor = 0;
        product = 0;
    }

    // Writes one device property; skipped (and logged) without a real device.
    function write(property: string, value): void {
        if (!present) {
            logged("pen: no tablet device, " + property + " not written");
            return;
        }
        let typed;
        if (typeof value === "boolean") {
            typed = new DBus.bool(value);
        } else {
            typed = new DBus.string(String(value));
        }
        properties(root + "/" + sysName, "Set",
                   [new DBus.string(deviceIface), new DBus.string(property), new DBus.variant(typed)], "(ssv)",
                   () => {
                       dev.logged("pen: " + property + " = " + value);
                       dev.refresh();
                   }, () => dev.logged("pen: writing " + property + " failed"));
    }

    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: dev.service
        path: dev.root
        iface: "org.kde.KWin.InputDeviceManager"

        function dbusdeviceAdded(sysName) {
            dev.refresh();
        }
        function dbusdeviceRemoved(sysName) {
            dev.refresh();
        }
    }

    Component.onCompleted: refresh()
}
