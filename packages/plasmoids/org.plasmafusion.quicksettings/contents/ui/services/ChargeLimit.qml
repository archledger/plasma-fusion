// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.plasma5support as P5Support

// Battery charge limit (research D-desktop "Add": a charge limit with a one-tap full charge in the
// quick settings; docs/parts/charge-limit.md). The value is the battery's stop threshold in sysfs,
// the one PowerDevil's Energy Saving page sets too: read without privileges, set with pkexec through
// /usr/libexec/plasma-fusion/plasma-fusion-charge-limit (polkit action org.plasmafusion.charge-limit,
// no password in the active session). Present only where the helper and its action are installed
// system-wide and a built-in battery has a stop threshold.
//
// plasmafusionrc [Battery]: ChargeLimit = the limit the tile turns on (80 by default, the last one
// picked); RestoreChargeLimit = the limit "Charge to 100 % once" puts back when the battery is full
// or the charger is unplugged (0: none pending; offered only while plugged in).
//
// Where TLP sets the thresholds (the helper prints "managed=tlp"), TLP writes them again at boot, on
// unplugging and on resume: the tile shows TLP's limit and offers no changes (`managedBy`).
Item {
    id: charge

    property bool present: false
    property int limit: 100
    property int preferred: 80
    property int restoreLimit: 0
    property bool busy: false
    // "tlp" when TLP sets the thresholds; nothing is changed from here then.
    property string managedBy: ""

    // From the battery service (Backend); batteryKnown once it has reported.
    property bool batteryKnown: false
    property int batteryPercent: 0
    property bool pluggedIn: false
    property bool batteryFull: false

    readonly property bool limited: present && limit < 100
    readonly property string helper: "/usr/libexec/plasma-fusion/plasma-fusion-charge-limit"
    readonly property string policy: "/usr/share/polkit-1/actions/org.plasmafusion.charge-limit.policy"
    readonly property string readCommand: "if test -x " + helper + " && test -f " + policy + "; then " + helper + " get; fi; "
        + "echo pref=$(kreadconfig6 --file plasmafusionrc --group Battery --key ChargeLimit --default 80); "
        + "echo restore=$(kreadconfig6 --file plasmafusionrc --group Battery --key RestoreChargeLimit --default 0)"

    property var handlers: ({})
    function run(command: string, handler): void {
        if (handler) {
            handlers[command] = handler;
        }
        source.connectSource(command);
    }
    P5Support.DataSource {
        id: source
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            const handler = charge.handlers[sourceName];
            delete charge.handlers[sourceName];
            disconnectSource(sourceName);
            if (handler) {
                handler(Number(data["exit code"]), String(data["stdout"] || ""));
            }
        }
    }

    function refresh(): void {
        run(readCommand + " # " + Date.now(), (code, out) => {
            let found = false;
            let manager = "";
            for (const line of out.split("\n")) {
                const fields = line.trim().split(/\s+/);
                if (/^\d+$/.test(fields[0]) && fields.length >= 2) {
                    limit = Number(fields[0]);
                    found = true;
                } else if (fields[0].startsWith("pref=")) {
                    const value = Number(fields[0].slice(5));
                    preferred = value >= 50 && value < 100 ? value : 80;
                } else if (fields[0].startsWith("managed=")) {
                    manager = fields[0].slice(8);
                } else if (fields[0].startsWith("restore=")) {
                    const value = Number(fields[0].slice(8));
                    restoreLimit = value >= 50 && value < 100 ? value : 0;
                }
            }
            present = found;
            managedBy = manager;
            busy = false;
            checkRestore(false);
        });
    }
    Component.onCompleted: refresh()

    // Sets the stop threshold (100: no limit), then reads it back.
    function setLimit(value: int): void {
        if (!present || busy || managedBy !== "") {
            return;
        }
        busy = true;
        let command = "pkexec " + helper + " set " + value + "; ";
        if (value < 100) {
            command += "kwriteconfig6 --file plasmafusionrc --group Battery --key ChargeLimit " + value + "; ";
        }
        console.info("quicksettings: charge limit " + (value < 100 ? value + " %" : "off"));
        run(command + "true # " + Date.now(), (code, out) => {
            // read back: a declined or failed pkexec leaves the old value
            charge.refresh();
        });
    }
    function setLimitAndForget(value: int): void {
        clearRestore();
        setLimit(value);
    }
    function toggle(): void {
        setLimitAndForget(limited ? 100 : preferred);
    }
    // Charge to 100 % once: the limit comes back when the battery is full or the charger is unplugged.
    function fullChargeOnce(): void {
        if (!limited || managedBy !== "") {
            return;
        }
        restoreLimit = limit;
        run("kwriteconfig6 --file plasmafusionrc --group Battery --key RestoreChargeLimit " + limit);
        setLimit(100);
    }
    function clearRestore(): void {
        if (restoreLimit > 0) {
            restoreLimit = 0;
            run("kwriteconfig6 --file plasmafusionrc --group Battery --key RestoreChargeLimit --delete");
        }
    }
    function checkRestore(unplugged: bool): void {
        if (!present || busy || managedBy !== "" || !batteryKnown || restoreLimit <= 0 || limit < 100) {
            return;
        }
        if (unplugged || batteryFull || batteryPercent >= 100 || !pluggedIn) {
            const value = restoreLimit;
            console.info("quicksettings: full charge once ended, limit " + value + " % again");
            clearRestore();
            setLimit(value);
        }
    }
    onBatteryKnownChanged: checkRestore(false)
    onBatteryFullChanged: checkRestore(false)
    onBatteryPercentChanged: checkRestore(false)
    onPluggedInChanged: {
        if (!pluggedIn) {
            checkRestore(true);
        }
    }
}
