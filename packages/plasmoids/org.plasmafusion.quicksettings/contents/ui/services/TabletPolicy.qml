// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus

// Tablet posture policies of quick settings (TABLET 3.3 and 4.6):
//
// - Keyboard policy (`keyboardPolicy`): KWin's `[Wayland] InputMethod` per posture. "tablet" (the
//   default): the Plasma keyboard in tablet posture, none on the laptop (the process stops);
//   "touch": always (KWin shows it on a touch or pen tap); "never": none. Written with
//   kwriteconfig6 --notify only when the value differs; `VirtualKeyboardMode` is never written
//   (it pops an OSD each time, F13).
// - The on-screen keyboard's state from KWin (org.kde.kwin.VirtualKeyboard on /VirtualKeyboard):
//   `oskAvailable`, `oskVisible`; `toggleOsk()` shows it now or hides it.
// - Rotation lock (F14, T19): lock = the current rotation kept and auto-rotation never; unlock =
//   auto-rotation in tablet mode and the normal rotation. Leaving tablet mode while locked turns
//   the screen back to normal and keeps the lock. State in plasmafusionrc [Tablet] RotationLocked.
// - Power button (TABLET2 P0): in tablet posture a press turns the screen off and locks it first,
//   as on a phone or tablet: PowerDevil's own defaults for touch devices (powerdevilrc
//   [<profile>][SuspendAndShutdown] PowerButtonAction 128 "toggle screen on/off",
//   [<profile>][Display] LockBeforeTurnOffDisplay true). Written per profile only where the user has
//   no value, recorded in plasmafusionrc [Tablet] PowerButtonWritten and removed again in laptop
//   posture (Plasma's logout prompt), unless the user changed them meanwhile.
// - Tablet mode setting (3.2): kwinrc [Input] TabletMode auto / on / off.
// - Full-screen apps (4.2, 4.9): the tablet script's global WindowMode, fullscreen / windowed,
//   written and applied through its shortcut.
//
// Everything runs inside the session (kscreen-doctor needs the session's display).
Item {
    id: policy

    property bool tablet: false
    // KWin has told the posture (FusionTablet.fromKWin): nothing is written before.
    property bool postureKnown: true
    property string keyboardPolicy: "tablet"
    // Name of the screen quick settings sits on (the rotation lock's fallback output).
    property string screenName: ""

    readonly property string oskDesktop: "/usr/share/applications/org.kde.plasma.keyboard.desktop"

    // ---- Commands
    function quote(value: string): string {
        return "'" + value.replace(/'/g, "'\\''") + "'";
    }
    property var handlers: ({})
    function run(command: string, handler) {
        if (handler) {
            handlers[command] = handler;
        }
        commands.connectSource(command);
    }
    P5Support.DataSource {
        id: commands
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            const handler = policy.handlers[sourceName];
            delete policy.handlers[sourceName];
            disconnectSource(sourceName);
            if (handler) {
                handler(Number(data["exit code"]), String(data["stdout"] || ""));
            }
        }
    }

    // ---- Keyboard policy
    property bool inputMethodKnown: false
    property string inputMethod: ""
    function wantedInputMethod(): string {
        switch (keyboardPolicy) {
        case "never":
            return "";
        case "touch":
            return oskDesktop;
        default:
            return tablet ? oskDesktop : "";
        }
    }
    function applyKeyboard() {
        if (!inputMethodKnown || !postureKnown) {
            return;
        }
        const want = wantedInputMethod();
        if (want === inputMethod) {
            return;
        }
        inputMethod = want;
        console.info("quicksettings: keyboard policy " + keyboardPolicy + ", " + (tablet ? "tablet" : "laptop")
                     + ": InputMethod " + (want === "" ? "off" : "plasma-keyboard"));
        run("kwriteconfig6 --notify --file kwinrc --group Wayland --key InputMethod " + quote(want));
    }
    onKeyboardPolicyChanged: Qt.callLater(applyKeyboard)
    onPostureKnownChanged: {
        Qt.callLater(applyKeyboard);
        Qt.callLater(applyPowerButton);
    }

    // ---- Power button
    // One shell run per posture change, under a lock: a quick fold and unfold cannot interleave two
    // runs' reads and writes (private session pb1: fold, unfold, fold 1 s apart).
    readonly property string powerButtonScript: [
        "exec 9>\"${XDG_RUNTIME_DIR:-/tmp}/plasma-fusion-power-button.lock\" && flock 9",
        "f=powerdevilrc; r=plasmafusionrc",
        "rec=$(kreadconfig6 --file $r --group Tablet --key PowerButtonWritten)",
        "if [ \"$1\" = tablet ]; then",
        "  for p in AC Battery LowBattery; do",
        "    if [ -z \"$(kreadconfig6 --file $f --group $p --group SuspendAndShutdown --key PowerButtonAction)\" ]; then",
        "      kwriteconfig6 --file $f --group $p --group SuspendAndShutdown --key PowerButtonAction 128; rec=\"$rec $p/button\"; fi",
        "    if [ -z \"$(kreadconfig6 --file $f --group $p --group Display --key LockBeforeTurnOffDisplay)\" ]; then",
        "      kwriteconfig6 --file $f --group $p --group Display --key LockBeforeTurnOffDisplay true; rec=\"$rec $p/lock\"; fi",
        "  done",
        "  kwriteconfig6 --file $r --group Tablet --key PowerButtonWritten \"$(echo $rec)\"",
        "else",
        "  for e in $rec; do p=${e%/*}",
        "    case $e in",
        "    */button) [ \"$(kreadconfig6 --file $f --group $p --group SuspendAndShutdown --key PowerButtonAction)\" = 128 ] &&",
        "      kwriteconfig6 --file $f --group $p --group SuspendAndShutdown --key PowerButtonAction --delete ;;",
        "    */lock) [ \"$(kreadconfig6 --file $f --group $p --group Display --key LockBeforeTurnOffDisplay)\" = true ] &&",
        "      kwriteconfig6 --file $f --group $p --group Display --key LockBeforeTurnOffDisplay --delete ;;",
        "    esac",
        "  done",
        "  [ -z \"$rec\" ] || kwriteconfig6 --file $r --group Tablet --key PowerButtonWritten --delete",
        "fi",
        "echo \"$1: $(echo $rec)\""
    ].join("\n")
    property string powerButtonPosture: ""
    function applyPowerButton() {
        if (!postureKnown) {
            return;
        }
        const want = tablet ? "tablet" : "laptop";
        if (want === powerButtonPosture) {
            return;
        }
        powerButtonPosture = want;
        run("bash -c " + quote(powerButtonScript) + " power-button " + want, (code, out) => {
            console.info("quicksettings: power button " + out.trim() + " (exit " + code + ")");
            // PowerDevil reads its profiles again (it may not run in a test session).
            DBus.SessionBus.asyncCall({
                "service": "org.kde.Solid.PowerManagement",
                "path": "/org/kde/Solid/PowerManagement",
                "iface": "org.kde.Solid.PowerManagement",
                "member": "refreshStatus",
                "arguments": []
            }, () => {}, () => {});
        });
    }

    // ---- On-screen keyboard state (KWin)
    property bool oskAvailable: false
    property bool oskVisible: false
    property bool oskActive: false
    function refreshOsk() {
        DBus.SessionBus.asyncCall({
            "service": "org.kde.KWin",
            "path": "/VirtualKeyboard",
            "iface": "org.freedesktop.DBus.Properties",
            "member": "GetAll",
            "arguments": [new DBus.string("org.kde.kwin.VirtualKeyboard")],
            "signature": "(s)"
        }, reply => {
            const props = reply.value;
            if (props) {
                policy.oskAvailable = props.available === true;
                policy.oskVisible = props.visible === true;
                policy.oskActive = props.active === true;
            }
        }, () => {});
    }
    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.kde.KWin"
        path: "/VirtualKeyboard"
        iface: "org.kde.kwin.VirtualKeyboard"
        function dbusavailableChanged() {
            policy.refreshOsk();
        }
        function dbusvisibleChanged() {
            policy.refreshOsk();
        }
        function dbusactiveChanged() {
            policy.refreshOsk();
        }
        function dbusenabledChanged() {
            policy.refreshOsk();
        }
    }
    function setOskProperty(name: string, value: bool) {
        DBus.SessionBus.asyncCall({
            "service": "org.kde.KWin",
            "path": "/VirtualKeyboard",
            "iface": "org.freedesktop.DBus.Properties",
            "member": "Set",
            "arguments": [new DBus.string("org.kde.kwin.VirtualKeyboard"), new DBus.string(name), new DBus.variant(new DBus.bool(value))],
            "signature": "(ssv)"
        }, () => policy.refreshOsk(), () => {});
    }
    // Shows the keyboard now (also without a text field), or hides it (TABLET 4.3).
    function toggleOsk() {
        if (oskVisible) {
            setOskProperty("active", false);
        } else {
            DBus.SessionBus.asyncCall({
                "service": "org.kde.KWin",
                "path": "/VirtualKeyboard",
                "iface": "org.kde.kwin.VirtualKeyboard",
                "member": "forceActivate",
                "arguments": []
            }, () => policy.refreshOsk(), () => {});
        }
    }

    // ---- Rotation lock
    property bool rotationLocked: false
    // The built-in output and its rotation, from kscreen-doctor -j.
    function withOutput(callback) {
        run("kscreen-doctor -j", (code, out) => {
            let name = "", rotation = 1, policyValue = -1;
            try {
                const outputs = JSON.parse(out).outputs || [];
                const enabled = outputs.filter(o => o.enabled !== false);
                const internal = enabled.find(o => /^(eDP|LVDS|DSI)/.test(String(o.name)))
                    || enabled.find(o => String(o.name) === policy.screenName) || enabled[0];
                if (internal) {
                    name = String(internal.name);
                    rotation = Number(internal.rotation) || 1;
                    policyValue = internal.autoRotatePolicy !== undefined ? Number(internal.autoRotatePolicy) : -1;
                }
            } catch (e) {
                console.info("quicksettings: kscreen-doctor -j unreadable (exit " + code + ")");
            }
            callback(name, rotation, policyValue);
        });
    }
    function rotationName(value: int): string {
        switch (value) {
        case 2:
            return "left";
        case 4:
            return "inverted";
        case 8:
            return "right";
        default:
            return "normal";
        }
    }
    function setRotationLocked(lock: bool) {
        withOutput((name, rotation) => {
            if (name === "") {
                return;
            }
            const o = "output." + name;
            const command = lock
                ? "kscreen-doctor " + quote(o + ".rotation." + rotationName(rotation)) + " " + quote(o + ".autoRotatePolicy.never")
                : "kscreen-doctor " + quote(o + ".autoRotatePolicy.inTabletMode") + " " + quote(o + ".rotation.normal");
            console.info("quicksettings: rotation " + (lock ? "locked at " + rotationName(rotation) : "unlocked") + " on " + name);
            run(command, (code, out) => {
                if (code !== 0) {
                    console.info("quicksettings: kscreen-doctor exit " + code + " for the rotation " + (lock ? "lock" : "unlock"));
                }
            });
            policy.rotationLocked = lock;
            run("kwriteconfig6 --file plasmafusionrc --group Tablet --key RotationLocked " + (lock ? "true" : "false"));
        });
    }
    // Leaving tablet mode while locked: back to the normal rotation, lock kept (so the laptop is
    // landscape and the next tablet session starts in landscape).
    onTabletChanged: {
        Qt.callLater(applyKeyboard);
        Qt.callLater(applyPowerButton);
        if (!tablet && rotationLocked) {
            withOutput((name, rotation) => {
                if (name !== "" && rotation !== 1) {
                    console.info("quicksettings: tablet mode ended with the rotation locked: " + name + " back to normal");
                    run("kscreen-doctor " + quote("output." + name + ".rotation.normal"), () => {});
                }
            });
        }
    }
    // The lock as KWin has it (autoRotatePolicy 0 never, 1 in tablet mode, 2 always), checked
    // when the sheet opens in tablet mode; outputs without the capability do not report it.
    function checkRotationLock() {
        withOutput((name, rotation, policyValue) => {
            if (policyValue >= 0) {
                policy.rotationLocked = policyValue === 0;
            }
        });
    }

    // ---- Tablet mode setting
    property string tabletModeSetting: "auto"
    function setTabletMode(value: string) {
        tabletModeSetting = value;
        console.info("quicksettings: tablet mode setting " + value);
        run("kwriteconfig6 --notify --file kwinrc --group Input --key TabletMode " + value);
    }
    function cycleTabletMode() {
        const order = ["auto", "on", "off"];
        setTabletMode(order[(order.indexOf(tabletModeSetting) + 1) % order.length]);
    }

    // ---- Full-screen apps (the tablet script's WindowMode)
    property string windowMode: "fullscreen"
    function setWindowMode(mode: string) {
        windowMode = mode;
        console.info("quicksettings: full-screen apps " + (mode === "fullscreen" ? "on" : "off"));
        run("kwriteconfig6 --notify --file kwinrc --group Script-plasmafusion-tablet --key WindowMode " + mode, () => {
            DBus.SessionBus.asyncCall({
                "service": "org.kde.kglobalaccel",
                "path": "/component/kwin",
                "iface": "org.kde.kglobalaccel.Component",
                "member": "invokeShortcut",
                "arguments": [new DBus.string("Plasma Fusion: Tablet Window Mode")],
                "signature": "(s)"
            }, () => {}, () => {});
        });
    }

    // The settings other tools may have changed (System Settings, kwriteconfig6), read again
    // whenever the sheet opens.
    function refresh() {
        run("kreadconfig6 --file kwinrc --group Script-plasmafusion-tablet --key WindowMode --default fullscreen", (code, out) => {
            policy.windowMode = out.trim() === "windowed" ? "windowed" : "fullscreen";
        });
        run("kreadconfig6 --file kwinrc --group Input --key TabletMode --default auto", (code, out) => {
            const value = out.trim();
            policy.tabletModeSetting = ["on", "off"].indexOf(value) >= 0 ? value : "auto";
        });
        refreshOsk();
    }

    Component.onCompleted: {
        run("kreadconfig6 --file kwinrc --group Script-plasmafusion-tablet --key WindowMode --default fullscreen", (code, out) => {
            policy.windowMode = out.trim() === "windowed" ? "windowed" : "fullscreen";
        });
        run("kreadconfig6 --file kwinrc --group Wayland --key InputMethod", (code, out) => {
            policy.inputMethod = out.trim();
            policy.inputMethodKnown = true;
            policy.applyKeyboard();
        });
        run("kreadconfig6 --file kwinrc --group Input --key TabletMode --default auto", (code, out) => {
            const value = out.trim();
            policy.tabletModeSetting = ["on", "off"].indexOf(value) >= 0 ? value : "auto";
        });
        run("kreadconfig6 --file plasmafusionrc --group Tablet --key RotationLocked --default false", (code, out) => {
            policy.rotationLocked = out.trim() === "true";
        });
        refreshOsk();
    }
}
