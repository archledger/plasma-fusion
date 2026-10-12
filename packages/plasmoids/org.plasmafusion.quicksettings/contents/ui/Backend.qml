// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus

import "components"
import "global"
import "../code/power.js" as Power
import "../code/dnd.js" as Dnd
import "../code/keepawake.js" as Timed

// Every data source behind one null-safe object. Each service lives in its own
// file and is loaded with a Loader, so a missing QML module (no Bluetooth stack,
// no KDE Connect, ...) only disables that one feature.
Item {
    id: backend

    // ---- Set by main.qml
    property bool popupOpen: false
    property bool showKeyboardLayout: true
    property bool keyboardLayoutAlways: true
    property bool showKdeConnect: true
    property bool showClipboard: true
    property bool showBatteryPercent: true
    property bool showNotifications: true
    // The tiles' order and the hidden tiles (contents/code/tiles.js; the widget's settings).
    property var tileOrder: []
    property var hiddenTiles: []
    // The sheet's edit mode asks main.qml to store a new order and hidden tiles.
    signal tileLayoutRequested(var order, var hidden)
    property string lightLookAndFeel: "org.plasmafusion.light.desktop"
    property string darkLookAndFeel: "org.plasmafusion.dark.desktop"
    // Page of the pop-up: "main", "wifi", "bluetooth", "audio", "power" (Keep awake), "profiles"
    // (Power mode), "devices", "display" or "clipboard".
    property string page: "main"
    // The page was opened on its own (the clipboard button, Meta+V), not from quick settings:
    // Escape closes the sheet instead of going back.
    property bool pageDirect: false
    property string audioPage: "output"
    // The pop-up was opened from the bell: show the notification list even when empty.
    property bool showEmptyNotifications: false
    // Tablet posture with the Notification Centre apart from the controls (TABLET2 S1): the sheet
    // shows no notification list.
    property bool notificationsApart: false
    // Tablet posture (FusionTablet) and whether it can change by itself; the screen's name.
    property bool tablet: false
    property bool postureKnown: true
    property bool tabletAvailable: false
    property string screenName: ""
    // This widget runs the session-wide jobs (main.qml, Instances).
    property bool leader: true
    property string keyboardPolicy: "tablet"
    // Phone and clipboard live in the sheet instead of the bar (tablet posture, or the top bar's
    // width budget at step 2).
    property bool barCompact: false
    // A pen is connected (the pen widget in the same bar says so); its menu opens on request.
    property bool penPresent: false
    signal penRequested()

    // Asks the owner to close the pop-up (after launching something).
    signal closeRequested()
    // A removable device was plugged in while the session runs (Disks & Devices).
    signal deviceAdded(string udi)
    // the controls sheet's "Notifications" switch (tablet posture, notifications apart)
    signal notificationCentreRequested()

    readonly property FusionPalette pal: FusionPalette {
        dark: {
            const c = Kirigami.Theme.backgroundColor;
            return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
        }
        accent: Kirigami.Theme.highlightColor
        accentSoft: Kirigami.Theme.hoverColor
        focus: Kirigami.Theme.focusColor
        link: Kirigami.Theme.linkColor
        fontFamily: Kirigami.Theme.defaultFont.family
    }

    function dbus(service: string, path: string, iface: string, member: string, args, signature: string) {
        const message = { service: service, path: path, iface: iface, member: member };
        if (args && args.length > 0) {
            message.arguments = args;
            message.signature = signature;
        }
        DBus.SessionBus.asyncCall(message);
    }

    // ------------------------------------------------------------------ loaders
    Loader { id: netLoader; asynchronous: true; source: "services/Network.qml" }
    Loader { id: audioLoader; asynchronous: true; source: "services/Audio.qml" }
    Loader { id: batteryLoader; asynchronous: true; source: "services/Battery.qml" }
    Loader { id: profilesLoader; asynchronous: true; source: "services/PowerProfiles.qml" }
    Connections {
        target: profilesLoader.item
        function onFailed(profile: string) {
            backend.profile.failedProfile = profile;
            profileFailedTimer.restart();
        }
    }
    Timer {
        id: profileFailedTimer
        interval: 5000
        onTriggered: backend.profile.failedProfile = ""
    }
    Loader { id: keepAwakeLoader; asynchronous: true; source: "services/KeepAwake.qml" }
    Loader { id: devicesLoader; asynchronous: true; source: "services/Devices.qml" }
    Connections {
        target: devicesLoader.item
        function onDeviceAdded(udi: string) {
            backend.deviceAdded(udi);
        }
    }
    Loader { id: displayLoader; asynchronous: true; source: "services/Display.qml" }
    Loader { id: mediaLoader; asynchronous: true; source: "services/Media.qml" }
    Loader { id: notifLoader; asynchronous: true; source: "services/Notifications.qml" }
    Loader { id: kbdLoader; asynchronous: true; source: "services/Keyboard.qml" }
    // Only when the phone button is wanted: the model D-Bus-activates kdeconnectd.
    Loader { id: phoneLoader; asynchronous: true; active: backend.showKdeConnect; source: "services/KdeConnect.qml" }
    Loader { id: btLoader; asynchronous: true; source: "services/Bluetooth.qml" }
    Loader { id: sessionLoader; asynchronous: true; source: "services/Session.qml" }
    Loader { id: execLoader; asynchronous: true; source: "services/Exec.qml" }
    Loader { id: tabletLoader; asynchronous: true; source: "services/TabletPolicy.qml" }
    Loader { id: chargeLoader; asynchronous: true; source: "services/ChargeLimit.qml" }
    // The panel this widget is in (main.qml): its system tray's hidden stock items are shown
    // while active (services/TrayItems.qml).
    property var containment: null
    Loader { id: trayItemsLoader; asynchronous: true; source: "services/TrayItems.qml" }
    Binding {
        target: trayItemsLoader.item
        property: "containment"
        value: backend.containment
        when: trayItemsLoader.item !== null
    }
    Binding {
        target: trayItemsLoader.item
        property: "tablet"
        value: backend.tablet
        when: trayItemsLoader.item !== null
    }
    readonly property var trayRevealed: trayItemsLoader.item ? trayItemsLoader.item.revealed : []
    // Plasma's clipboard module (Klipper's history), for the clipboard button and Meta+V (which
    // opens the sheet also without the button).
    Loader { id: clipboardLoader; asynchronous: true; source: "services/Clipboard.qml" }
    Binding {
        target: chargeLoader.item
        property: "batteryKnown"
        value: backend.battery.present
        when: chargeLoader.item !== null
    }
    Binding {
        target: chargeLoader.item
        property: "batteryPercent"
        value: backend.battery.percent
        when: chargeLoader.item !== null
    }
    Binding {
        target: chargeLoader.item
        property: "pluggedIn"
        value: backend.battery.pluggedIn
        when: chargeLoader.item !== null
    }
    Binding {
        target: chargeLoader.item
        property: "batteryFull"
        value: backend.battery.full
        when: chargeLoader.item !== null
    }
    readonly property var tabletPolicy: tabletLoader.item
    Binding {
        target: tabletLoader.item
        property: "tablet"
        value: backend.tablet
        when: tabletLoader.item !== null
    }
    Binding {
        target: tabletLoader.item
        property: "postureKnown"
        value: backend.postureKnown
        when: tabletLoader.item !== null
    }
    Binding {
        target: tabletLoader.item
        property: "keyboardPolicy"
        value: backend.keyboardPolicy
        when: tabletLoader.item !== null
    }
    Binding {
        target: tabletLoader.item
        property: "screenName"
        value: backend.screenName
        when: tabletLoader.item !== null
    }
    Binding {
        target: tabletLoader.item
        property: "leader"
        value: backend.leader
        when: tabletLoader.item !== null
    }

    readonly property var sessionService: sessionLoader.item
    readonly property var execService: execLoader.item

    Binding {
        target: netLoader.item
        property: "listVisible"
        value: backend.popupOpen && backend.page === "wifi"
        when: netLoader.item !== null
    }
    Binding {
        target: btLoader.item
        property: "listVisible"
        value: backend.popupOpen && backend.page === "bluetooth"
        when: btLoader.item !== null
    }
    Binding {
        target: profilesLoader.item
        property: "silent"
        value: backend.popupOpen
        when: profilesLoader.item !== null
    }
    Binding {
        target: displayLoader.item
        property: "silent"
        value: backend.popupOpen
        when: displayLoader.item !== null
    }

    function openSettings(kcm: string, args) {
        if (sessionService) {
            sessionService.openSettings(kcm, args || []);
        }
        backend.closeRequested();
    }
    function run(command: string): bool {
        if (execService) {
            execService.run(command);
            return true;
        }
        return false;
    }

    // ------------------------------------------------------------------ network
    readonly property var net: QtObject {
        readonly property var s: netLoader.item
        readonly property bool available: !!s
        readonly property bool wifiDevice: s ? s.wifiDevice : false
        readonly property bool wifiEnabled: s ? s.wifiEnabled : false
        readonly property bool wifiHwEnabled: s ? s.wifiHwEnabled : false
        readonly property bool airplane: s ? s.airplane : false
        readonly property bool airplaneAvailable: s ? s.airplaneAvailable : false
        // The radios on before airplane mode are kept for every screen's widget (Instances, and in
        // the widgets' settings across a plasmashell restart, main.qml), so the one that ends it
        // brings them back; with no record (airplane mode started elsewhere) they all come back on.
        // Bluetooth is read and set over BlueZ's D-Bus itself (the adapters powered on), not
        // through the optional Bluetooth service, which may not be loaded or installed, and not
        // through plasma-nm's handler either: its airplane step powers the adapters off after
        // its own asynchronous BlueZ calls, which a quick exit could cross; here every Powered
        // goes out on the one connection, in order.
        property bool airplaneSwitching: false
        function setAirplaneMode(on: bool): void {
            if (!s || airplaneSwitching) {
                return;
            }
            airplaneSwitching = true;
            bluetoothRetry.drop();
            if (on) {
                // The radios as they are now, before BlueZ answers: airplane mode started elsewhere
                // meanwhile has turned them off, and is not this widget's to record.
                const wifi = s.wifiEnabled;
                const wwan = s.wwanEnabled;
                backend.poweredBluetoothAdapters(adapters => {
                    airplaneSwitching = false;
                    if (s.airplane) {
                        return;
                    }
                    // No answer from BlueZ (absent, or failed): every adapter comes back, as with
                    // no record, rather than none.
                    Instances.airplaneRestore = { wifi: wifi, wwan: wwan, bluetooth: adapters === null ? true : adapters };
                    (adapters || []).forEach(path => backend.powerBluetoothAdapter(path, false));
                    s.enterAirplaneMode();
                });
                return;
            }
            const restore = Instances.airplaneRestore;
            Instances.airplaneRestore = null;
            s.leaveAirplaneMode(restore ? restore.wifi : true, restore ? restore.wwan : true);
            // The record's Bluetooth: the adapters that were on; true (a record saved before this,
            // one boolean for the Bluetooth service's state, or BlueZ not answering when airplane
            // mode started) or no record: every adapter; false or none listed: none.
            const bluetooth = restore ? restore.bluetooth : true;
            if (bluetooth !== true && !(Array.isArray(bluetooth) && bluetooth.length > 0)) {
                airplaneSwitching = false;
                return;
            }
            // A soft rfkill block set meanwhile (the Bluetooth tile, bluedevil's switch, rfkill)
            // makes BlueZ refuse Powered: cleared first, through the Bluetooth service when it is
            // loaded (a hard block stays, and so does Bluetooth off).
            backend.bt.unblock(() => {
                // Airplane mode back on while the block was clearing (another screen's widget,
                // the setting from elsewhere): nothing to power on any more.
                if (s.airplane) {
                    airplaneSwitching = false;
                    return;
                }
                if (Array.isArray(bluetooth)) {
                    bluetooth.forEach(path => backend.powerBluetoothAdapter(path, true));
                    airplaneSwitching = false;
                    return;
                }
                backend.powerAllBluetoothAdapters(5, () => { airplaneSwitching = false; });
            });
        }
        readonly property string ssid: s ? s.ssid : ""
        readonly property bool connecting: s ? s.connecting : false
        readonly property string kind: s ? s.kind : "none"
        readonly property int level: s ? s.level : 0
        readonly property var activeModel: s ? s.activeModel : null
        readonly property var otherModel: s ? s.otherModel : null
        readonly property var vpnModel: s ? s.vpnModel : null
        readonly property int vpnCount: s ? s.vpnCount : 0
        readonly property bool scanning: s ? s.scanning : false
        readonly property bool checked: wifiDevice && wifiEnabled && !airplane
        readonly property bool hotspotSupported: s ? s.hotspotSupported : false
        readonly property bool hotspotActive: s ? s.hotspotActive : false
        readonly property bool hotspotStarting: s ? s.hotspotStarting : false
        readonly property bool hotspotReady: hotspotActive
            || (wifiDevice && wifiEnabled && wifiHwEnabled && !airplane && hotspotSupported)
        readonly property string hotspotName: s ? s.hotspotName : ""
        readonly property string hotspotError: s && s.hotspotFailedToStart
            ? i18nc("@info", "The hotspot could not start") : ""
        // plasma-nm only offers a hotspot on a free radio, or while the connection runs over
        // something else; with one radio that is connected, Wi-Fi itself is the connection.
        readonly property bool hotspotRadioBusy: !hotspotSupported && kind === "wifi"
        readonly property string hotspotSubtitle: {
            if (hotspotActive) { return i18nc("@info:status hotspot", "On"); }
            if (hotspotStarting) { return i18nc("@info:status hotspot", "Starting…"); }
            if (!wifiDevice) { return i18nc("@info:status hotspot", "No Wi‑Fi radio"); }
            if (airplane) { return i18nc("@info:status hotspot", "Airplane mode"); }
            if (!wifiEnabled || !wifiHwEnabled) { return i18nc("@info:status hotspot", "Wi‑Fi is off"); }
            if (hotspotRadioBusy) { return i18nc("@info:status hotspot", "Wi‑Fi in use"); }
            if (!hotspotSupported) { return i18nc("@info:status hotspot", "Unavailable"); }
            if (hotspotError) { return i18nc("@info:status hotspot", "Failed to start"); }
            return i18nc("@info:status hotspot", "Off");
        }
        readonly property string hotspotHint: {
            if (hotspotActive) {
                return i18nc("@info %1 is the hotspot network name", "Sharing this computer's connection as “%1”", hotspotName);
            }
            if (hotspotRadioBusy) {
                return i18nc("@info", "The Wi‑Fi radio is connected to a network. Disconnect it or use a cable to share the connection.");
            }
            if (wifiDevice && wifiEnabled && wifiHwEnabled && !airplane && !hotspotSupported) {
                return i18nc("@info", "This Wi‑Fi radio cannot run a hotspot");
            }
            return i18nc("@info", "Share this computer's connection over Wi‑Fi");
        }
        function toggleHotspot(): void { if (s) { s.toggleHotspot(); } }
        function hotspotPassword(): string { return s ? s.hotspotPassword() : ""; }
        function configureHotspot(name: string, password: string): bool {
            return s ? s.configureHotspot(name, password) : false;
        }
        readonly property string subtitle: {
            if (!available) {
                return i18nc("@info:status network", "Unavailable");
            }
            if (airplane) {
                return i18nc("@info:status", "Airplane mode");
            }
            if (!wifiDevice) {
                return kind === "wired" ? i18nc("@info:status", "Wired connection") : i18nc("@info:status", "Unavailable");
            }
            if (!wifiHwEnabled) {
                return i18nc("@info:status Wi-Fi switched off by a hardware switch", "Off (hardware switch)");
            }
            if (!wifiEnabled) {
                return i18nc("@info:status Wi-Fi", "Off");
            }
            if (connecting) {
                return i18nc("@info:status", "Connecting…");
            }
            if (ssid.length > 0) {
                return ssid;
            }
            if (hotspotActive) {
                return i18nc("@info:status Wi-Fi", "Hotspot on");
            }
            return i18nc("@info:status Wi-Fi", "Not connected");
        }
        function setWifiEnabled(on: bool) {
            if (s) {
                s.setWifiEnabled(on);
            }
        }
        function toggle() {
            if (s && wifiDevice && wifiHwEnabled && !airplane) {
                s.setWifiEnabled(!wifiEnabled);
            }
        }
        function scan() {
            if (s) {
                s.scan();
            }
        }
        function activate(connectionPath: string, devicePath: string, specificPath: string) {
            if (s) {
                s.activate(connectionPath, devicePath, specificPath);
            }
        }
        function addAndActivate(devicePath: string, specificPath: string, password: string) {
            if (s) {
                s.addAndActivate(devicePath, specificPath, password);
            }
        }
        function deactivate(connectionPath: string, devicePath: string) {
            if (s) {
                s.deactivate(connectionPath, devicePath);
            }
        }
        function setStatistics(devicePath: string, on: bool) {
            if (s) {
                s.setStatistics(devicePath, on);
            }
        }
        function openSettings() {
            backend.openSettings("kcm_networkmanagement", []);
        }
    }

    // ------------------------------------------------------------------ audio
    readonly property var audio: QtObject {
        readonly property var s: audioLoader.item
        readonly property bool available: s ? s.available : false
        readonly property real volume: s ? s.volume : 0
        readonly property bool muted: s ? s.muted : true
        readonly property string deviceName: s ? s.deviceName : ""
        readonly property var sinkModel: s ? s.sinkModel : null
        readonly property int sinkCount: s ? s.sinkCount : 0
        readonly property bool inputAvailable: s ? s.inputAvailable : false
        readonly property real inputVolume: s ? s.inputVolume : 0
        readonly property bool inputMuted: s ? s.inputMuted : true
        readonly property string inputDescription: s ? s.inputDescription : ""
        readonly property var sourceModel: s ? s.sourceModel : null
        readonly property var cardModel: s ? s.cardModel : null
        readonly property var playbackModel: s ? s.playbackModel : null
        readonly property var recordingModel: s ? s.recordingModel : null
        readonly property real normal: s ? s.normal : 65536
        readonly property real maximum: s ? s.maximum : 1
        function setInputVolume(fraction: real): void { if (s) { s.setInputVolume(fraction); } }
        function toggleInputMute(): void { if (s) { s.toggleInputMute(); } }
        function setStreamVolume(stream: var, fraction: real): void { if (s) { s.setStreamVolume(stream, fraction); } }
        function toggleStreamMute(stream: var): void { if (s) { s.toggleStreamMute(stream); } }
        function routeStream(stream: var, index: int): void { if (s) { s.routeStream(stream, index); } }
        function setVolume(fraction: real) {
            if (s) {
                s.setVolume(fraction);
            }
        }
        function toggleMute() {
            if (s) {
                s.toggleMute();
            }
        }
        function setDefault(pulseObject) {
            if (s) {
                s.setDefault(pulseObject);
            }
        }
        function openSettings() {
            backend.openSettings("kcm_pulseaudio", []);
        }
    }

    // ------------------------------------------------------------------ battery
    readonly property var battery: QtObject {
        readonly property var s: batteryLoader.item
        readonly property bool present: s ? s.present : false
        readonly property int percent: s ? s.percent : 0
        readonly property bool charging: s ? s.charging : false
        readonly property bool pluggedIn: s ? s.pluggedIn : false
        readonly property bool full: s ? s.full : false
        readonly property real remainingMsec: s ? s.remainingMsec : 0
        function openSettings() {
            backend.openSettings("kcm_powerdevilprofilesconfig", []);
        }
    }

    // ------------------------------------------------------------------ charge limit
    readonly property var charge: QtObject {
        readonly property var s: chargeLoader.item
        readonly property bool present: s ? s.present : false
        readonly property bool limited: s ? s.limited : false
        readonly property int limit: s ? s.limit : 100
        readonly property int preferred: s ? s.preferred : 80
        readonly property bool fullOnce: s ? s.restoreLimit > 0 : false
        readonly property bool busy: s ? s.busy : false
        // TLP sets the thresholds here (services/ChargeLimit.qml): shown, not changed.
        readonly property bool managed: s ? s.managedBy !== "" : false
        readonly property string subtitle: {
            if (managed) {
                return limited ? i18nc("@info:status battery charge limit set by the TLP power tool, %1 percent", "TLP: stops at %1 %", limit)
                               : i18nc("@info:status battery charge limit set by the TLP power tool", "TLP: no limit");
            }
            if (fullOnce) {
                return i18nc("@info:status battery charge limit", "Charging to 100 % once");
            }
            return limited ? i18nc("@info:status battery charge limit, %1 percent", "Stops at %1 %", limit)
                           : i18nc("@info:status battery charge limit", "Off");
        }
        function toggle() {
            if (s) {
                s.toggle();
            }
        }
        function setLimit(value: int) {
            if (s) {
                s.setLimitAndForget(value);
            }
        }
        function fullChargeOnce() {
            if (s) {
                s.fullChargeOnce();
            }
        }
        function refresh() {
            if (s) {
                s.refresh();
            }
        }
        function openSettings() {
            backend.openSettings("kcm_powerdevilprofilesconfig", []);
        }
    }

    // ------------------------------------------------------------------ brightness
    readonly property var display: QtObject {
        readonly property var s: displayLoader.item
        readonly property bool brightnessAvailable: s ? s.brightnessAvailable : false
        readonly property real brightness: s ? s.brightness : 0
        readonly property string label: s ? s.displayLabel : ""
        readonly property var displaysModel: s ? s.displaysModel : null
        readonly property int displayCount: s ? s.displayCount : 0
        readonly property bool keyboardAvailable: s ? s.keyboardAvailable : false
        readonly property int keyboardValue: s ? s.keyboardValue : 0
        readonly property int keyboardMax: s ? s.keyboardMax : 0
        // The Brightness page has more than the main slider: another display or a keyboard light.
        readonly property bool more: displayCount > 1 || keyboardAvailable
        function setBrightness(fraction: real) {
            if (s) {
                s.setBrightness(fraction);
            }
        }
        function setDisplayBrightness(name: string, value: int) { if (s) { s.setDisplayBrightness(name, value); } }
        function setKeyboardBrightness(value: int) { if (s) { s.setKeyboardBrightness(value); } }
    }

    // ------------------------------------------------------------------ night light
    readonly property var night: QtObject {
        readonly property var s: displayLoader.item
        readonly property bool available: s ? s.nightAvailable : false
        readonly property bool enabled: s ? s.nightEnabled : false
        readonly property bool inhibited: s ? s.nightInhibited : false
        readonly property int mode: s ? s.nightMode : 0
        readonly property bool daylight: s ? s.nightDaylight : true
        readonly property bool warm: s ? s.nightActive : false
        readonly property double nextTransition: s ? s.nightNextTransition : 0
        readonly property bool checked: available && enabled && !inhibited && (mode === 3 || warm || !daylight)
        readonly property string subtitle: {
            if (!available) {
                return i18nc("@info:status Night Light", "Unavailable");
            }
            if (!enabled) {
                return i18nc("@info:status Night Light", "Off");
            }
            if (inhibited) {
                return i18nc("@info:status Night Light", "Paused");
            }
            if (mode === 3) {
                return i18nc("@info:status Night Light", "On");
            }
            const time = nextTransition > 0
                ? Qt.formatTime(new Date(nextTransition), Qt.locale().timeFormat(Locale.ShortFormat))
                : "";
            if (checked) {
                return mode === 2 && time ? i18nc("@info:status Night Light, %1 is a time", "Until %1", time)
                                          : i18nc("@info:status Night Light", "Until sunrise");
            }
            return mode === 2 && time ? i18nc("@info:status Night Light, %1 is a time", "From %1", time)
                                      : i18nc("@info:status Night Light", "From sunset");
        }
        function toggle() {
            if (!available) {
                backend.openSettings("kcm_nightlight", []);
                return;
            }
            if (!enabled) {
                // KWin's Night Light reloads its settings through KConfigWatcher, which
                // only hears writes made with --notify (a plain write or KWin's
                // reconfigure() leaves it off).
                if (!backend.run("kwriteconfig6 --notify --file kwinrc --group NightColor --key Active true")) {
                    backend.openSettings("kcm_nightlight", []);
                }
                return;
            }
            if (s) {
                s.toggleNightLightInhibition();
            }
        }
        function openSettings() {
            backend.openSettings("kcm_nightlight", []);
        }
    }
    // ------------------------------------------------------------------ do not disturb
    readonly property var dnd: QtObject {
        readonly property var s: notifLoader.item
        readonly property bool available: s ? s.serverValid : false
        readonly property bool active: s ? s.dndActive : false
        readonly property string untilText: s ? s.dndUntilText : ""
        // Why it is on besides a time (an app holds it, mirrored screens, a full screen window), in
        // the stock applet's words.
        readonly property var reasons: s ? s.dndReasons : []
        readonly property string subtitle: {
            if (!active) {
                return i18nc("@info:status Do not disturb", "Off");
            }
            if (untilText !== "") {
                return i18nc("@info:status Do not disturb, %1 is a time", "Until %1", untilText);
            }
            return reasons.length > 0 ? reasons[0] : i18nc("@info:status Do not disturb", "On");
        }
        // The whole state in one line, as the stock applet's header puts it.
        readonly property string description: {
            if (!active) {
                return "";
            }
            const parts = untilText !== "" ? [i18nc("@info:status Do not disturb, %1 is a time", "Until %1", untilText)] : [];
            return parts.concat(reasons).join(" · ");
        }
        function toggle() {
            if (s) {
                s.toggleDnd();
            }
        }
        // G18 and the stock applet's choices (contents/code/dnd.js): [{id, until}] at `now` (a Date).
        function choices(now: var): var {
            return Dnd.choices(now);
        }
        // The choice `id` from this moment, not from when the choices were drawn: "For 1 hour" lasts
        // an hour from the click, and a choice no longer offered ("this evening" after 20:00) does
        // nothing.
        function choose(id: string): bool {
            const choice = Dnd.choices(new Date()).find(c => c.id === id);
            return !!choice && !!s && s.dndUntil(choice.until);
        }
        function openSettings() {
            backend.openSettings("kcm_notifications", []);
        }
    }

    // BlueZ's adapters ([{path, powered}]; [] with none, null when BlueZ gave no answer: not
    // running, not installed, or the call failed) and their power, as plasma-nm's handler reads
    // and sets them for airplane mode.
    function bluetoothAdapters(done): void {
        DBus.SystemBus.asyncCall({
            "service": "org.bluez",
            "path": "/",
            "iface": "org.freedesktop.DBus.ObjectManager",
            "member": "GetManagedObjects",
            "arguments": []
        }, reply => {
            const objects = reply.value || {};
            const adapters = [];
            for (const path in objects) {
                const adapter = objects[path] ? objects[path]["org.bluez.Adapter1"] : undefined;
                if (adapter !== undefined) {
                    adapters.push({ path: path, powered: adapter["Powered"] === true });
                }
            }
            done(adapters);
        }, reply => {
            console.warn("quicksettings: BlueZ adapters not read: " + reply.error.name);
            done(null);
        });
    }
    function poweredBluetoothAdapters(done): void {
        bluetoothAdapters(adapters => done(adapters === null ? null : adapters.filter(a => a.powered).map(a => a.path)));
    }
    function powerBluetoothAdapter(path: string, on: bool): void {
        powerBluetoothAdapterTries(path, on, 3);
    }
    function powerBluetoothAdapterTries(path: string, on: bool, left: int): void {
        DBus.SystemBus.asyncCall({
            "service": "org.bluez",
            "path": path,
            "iface": "org.freedesktop.DBus.Properties",
            "member": "Set",
            "arguments": [new DBus.string("org.bluez.Adapter1"), new DBus.string("Powered"), new DBus.variant(on)],
            "signature": "(ssv)"
        }, () => {}, reply => {
            // Refused while BlueZ is still applying the previous change to the adapter
            // (org.bluez.Error.Busy, an exit right after the entry): powering on is asked again a
            // few times; powering off is not, a late one could cross an exit.
            if (on && left > 0) {
                bluetoothRetry.add(() => backend.powerBluetoothAdapterTries(path, true, left - 1));
            } else {
                console.warn("quicksettings: BlueZ Powered not set on " + path + ": " + reply.error.name);
            }
        });
    }
    // Every adapter on, for a restore with no list (no record, or an earlier one). The list is
    // asked again a few times when BlueZ gives none (restarting): the record is gone by now, so
    // this is the last chance; done is called after the first answer, the retries run by
    // themselves and are dropped once airplane mode is on again.
    function powerAllBluetoothAdapters(left: int, done): void {
        bluetoothAdapters(adapters => {
            if (adapters !== null) {
                if (!backend.net.airplane) {
                    adapters.forEach(a => backend.powerBluetoothAdapter(a.path, true));
                }
            } else if (left > 0) {
                bluetoothRetry.add(() => backend.powerAllBluetoothAdapters(left - 1, () => {}));
            } else {
                console.warn("quicksettings: BlueZ adapters not read, Bluetooth left as it is");
            }
            done();
        });
    }
    // Bluetooth asked again a little later: a power-on BlueZ refused, or an adapter list it did
    // not give. Dropped when airplane mode starts again (this widget's switch, another screen's,
    // or the setting from elsewhere), so nothing late crosses that entry.
    Timer {
        id: bluetoothRetry
        interval: 400
        property var pending: []
        function add(action): void {
            pending.push(action);
            restart();
        }
        function drop(): void {
            stop();
            pending = [];
        }
        onTriggered: {
            const again = pending;
            pending = [];
            if (!backend.net.airplane) {
                again.forEach(action => action());
            }
        }
    }

    // Airplane mode ended by anything else (the stock widget, nmcli): the record is stale. Started
    // by anything else: a Bluetooth retry still pending here would cross it.
    Connections {
        target: backend.net
        function onAirplaneChanged() {
            if (backend.net.airplane) {
                bluetoothRetry.drop();
            } else if (Instances.airplaneRestore) {
                Instances.airplaneRestore = null;
            }
        }
    }

    // ------------------------------------------------------------------ power profile
    readonly property var profile: QtObject {
        readonly property var s: profilesLoader.item
        readonly property bool available: s ? s.available : false
        readonly property string active: s ? s.active : ""
        readonly property bool checked: available && active !== "" && active !== "balanced"
        readonly property string inhibitionReason: s ? s.inhibitionReason : ""
        readonly property string degradationReason: s ? s.degradationReason : ""
        readonly property var holds: s ? Power.holds(s.holds) : []
        // A refused switch shows on the tile for a few seconds (the profile's id).
        property string failedProfile: ""
        function profileName(profile: string): string {
            switch (profile) {
            case "power-saver":
                return i18nc("@info:status power profile", "Power saver");
            case "performance":
                return i18nc("@info:status power profile", "Performance");
            case "balanced":
                return i18nc("@info:status power profile", "Balanced");
            default:
                return profile;
            }
        }
        readonly property string subtitle: {
            if (!available) {
                return i18nc("@info:status power profiles", "Unavailable");
            }
            if (failedProfile !== "") {
                return i18nc("@info:status %1 power profile name", "Couldn't switch to %1", profileName(failedProfile));
            }
            return profileName(active);
        }
        // Why Performance cannot be chosen (empty when it can), in the stock Power and Battery
        // widget's wording.
        readonly property string inhibitionNote: {
            switch (inhibitionReason) {
            case "":
                return "";
            case "lap-detected":
                return i18nc("@info:tooltip", "Performance mode has been disabled to reduce heat generation because the computer has detected that it may be sitting on your lap.");
            case "high-operating-temperature":
                return i18nc("@info:tooltip", "Performance mode is unavailable because the computer is running too hot.");
            default:
                return i18nc("@info:tooltip", "Performance mode is unavailable.");
            }
        }
        // That, why Performance may be slower, and which applications hold a profile.
        readonly property string note: {
            const lines = inhibitionNote !== "" ? [inhibitionNote] : [];
            if (active === "performance" && degradationReason !== "") {
                switch (degradationReason) {
                case "lap-detected":
                    lines.push(i18nc("@info:tooltip", "Performance may be lowered to reduce heat generation because the computer has detected that it may be sitting on your lap."));
                    break;
                case "high-operating-temperature":
                    lines.push(i18nc("@info:tooltip", "Performance may be reduced because the computer is running too hot."));
                    break;
                default:
                    lines.push(i18nc("@info:tooltip", "Performance may be reduced."));
                }
            }
            for (const h of holds) {
                lines.push(i18nc("@info:tooltip %1 application name, %2 power profile name", "%1 has requested %2", h.name, profileName(h.profile)));
            }
            return lines.join("\n");
        }
        // The chooser's rows ([{profile, active, enabled}]): Performance is listed but cannot be
        // chosen while the daemon inhibits it.
        readonly property var options: s ? Power.options(s.list, active, inhibitionReason) : []
        // The tile's body: back to Balanced, or from Balanced to the last other profile chosen
        // (shared by every widget, for this session), so Balanced to Power saver never passes
        // through Performance. Chosen here, by the user: a profile an application holds for a
        // while (a game's Performance) or PowerDevil's own for the power source is not a choice.
        readonly property string toggleTarget: s ? Power.toggleTarget(s.list, active, inhibitionReason, Instances.lastPowerProfile) : ""
        function switchTo(profile: string) {
            failedProfile = "";
            if (profile !== "balanced") {
                Instances.lastPowerProfile = profile;
            }
            s.setProfile(profile);
        }
        function setProfile(profile: string) {
            if (!s || !available) {
                backend.openSettings("kcm_powerdevilprofilesconfig", []);
                return;
            }
            // A refused switch shows on the tile and the page for a few seconds.
            const row = options.find(o => o.profile === profile);
            if (row && row.enabled && !row.active) {
                switchTo(profile);
            }
        }
        function toggle() {
            if (!s || !available) {
                backend.openSettings("kcm_powerdevilprofilesconfig", []);
                return;
            }
            if (toggleTarget !== "") {
                switchTo(toggleTarget);
            }
        }
        function openSettings() {
            backend.openSettings("kcm_powerdevilprofilesconfig", []);
        }
    }

    // ------------------------------------------------------------------ manual sleep and lock inhibition
    readonly property var keepAwake: QtObject {
        readonly property var s: keepAwakeLoader.item
        readonly property bool available: s ? s.available : false
        readonly property bool active: s ? s.active : false
        readonly property var inhibitors: s ? s.inhibitors : []
        function setAllowed(appName: string, reason: string, allowed: bool): void {
            if (s) { s.setAllowed(appName, reason, allowed); }
        }
        // A timed Keep awake (F7): its end (ms since the epoch, 0 until turned off), the minutes
        // left and both as text.
        readonly property double until: s ? s.until : 0
        readonly property bool timed: active && until > 0
        readonly property int minutesLeft: s ? s.minutesLeft : 0
        readonly property string leftText: backend.durationText(minutesLeft)
        readonly property string untilText: timed ? Qt.formatTime(new Date(until), Qt.locale().timeFormat(Locale.ShortFormat)) : ""
        readonly property string subtitle: !available ? i18nc("@info:status Keep awake", "Unavailable")
                                         : timed ? i18nc("@info:status Keep awake, %1 remaining time", "%1 left", leftText)
                                         : active ? i18nc("@info:status Keep awake", "On")
                                                  : i18nc("@info:status Keep awake", "Off")
        // The status pill's tooltip line while it is on.
        readonly property string toolTipLine: !active ? ""
            : timed ? i18nc("@info:tooltip %1 remaining time, %2 a time of day", "Keep awake: sleep and automatic screen locking are blocked for %1 more, until %2", leftText, untilText)
                    : i18nc("@info:tooltip", "Keep awake: sleep and automatic screen locking are blocked")
        readonly property string reason: i18nc("@info reason for manual power inhibition", "Manually block sleep and screen locking")
        function toggle(): void {
            if (s) {
                s.toggle(reason);
            }
        }
        // For a while: hours from now, until a time of day (minutes after midnight, today or
        // tomorrow), or until turned off (on stays on).
        function forHours(hours: int): void {
            if (s) {
                s.keepAwakeUntil(reason, Date.now() + hours * Timed.HOUR);
            }
        }
        function untilMinuteOfDay(minute: int): void {
            if (s) {
                s.keepAwakeUntil(reason, Timed.untilTime(new Date(), minute));
            }
        }
        function untilTurnedOff(): void {
            if (s) {
                s.keepAwakeUntil(reason, 0);
            }
        }
        // Testing only (debugAction "keepawake:SECONDS", main.qml): a short timed Keep awake.
        function forSeconds(seconds: int): void {
            if (s && seconds > 0) {
                s.keepAwakeUntil(reason, Date.now() + seconds * 1000);
            }
        }
        function refresh(): void {
            if (s) {
                s.tick();
            }
        }
    }
    // The minutes left shown again when the sheet opens (after a suspend the timer may be late).
    onPopupOpenChanged: {
        if (popupOpen) {
            keepAwake.refresh();
        }
    }
    // "45 min", "1 h", "1 h 30 min": the hours and the minutes each with their plural form (Polish,
    // Russian, Czech or Arabic words change with the number), joined by a translatable "%1 %2".
    function durationText(minutes: int): string {
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        const hours = i18ncp("@info remaining time, hours", "%1 h", "%1 h", h);
        const mins = i18ncp("@info remaining time, minutes", "%1 min", "%1 min", m);
        if (h === 0) {
            return mins;
        }
        return m === 0 ? hours : i18nc("@info remaining time, %1 hours part, %2 minutes part", "%1 %2", hours, mins);
    }

    // ------------------------------------------------------------------ disks & devices
    readonly property var devices: QtObject {
        readonly property var s: devicesLoader.item
        readonly property bool available: !!s
        readonly property var list: s ? s.list : []
        // Count and subtitle from the list itself: a separate count can change first.
        readonly property int count: list.length
        readonly property bool anyMounted: list.some(e => e.mounted)
        readonly property string subtitle: list.length === 0 ? i18nc("@info:status Disks & Devices", "None")
            : list.length === 1 ? list[0].name
            : i18ncp("@info:status Disks & Devices", "%1 device", "%1 devices", list.length)
        function open(udi: string): void { if (s) { s.open(udi); } }
        function mount(udi: string): void { if (s) { s.mount(udi); } }
        function unmount(udi: string): void { if (s) { s.unmount(udi); } }
        function refresh(): void { if (s) { s.refresh(); } }
        function openSettings(): void { backend.openSettings("kcm_device_automounter", []); }
    }

    // ------------------------------------------------------------------ dark style
    readonly property var darkStyle: QtObject {
        readonly property var s: displayLoader.item
        readonly property bool checked: backend.pal.dark
        readonly property string subtitle: checked ? i18nc("@info:status Dark style", "On") : i18nc("@info:status Dark style", "Off")
        function toggle() {
            const wantDark = !checked;
            const current = s ? String(s.currentTheme) : "";
            const other = s ? String(s.otherTheme) : "";
            const fusionCurrent = current.indexOf("Plasma Fusion") === 0;
            const fusionPairing = fusionCurrent && other.indexOf("Plasma Fusion") === 0;
            // 1. The light/dark pairing in kdeglobals is set up (for example by the
            //    Plasma Fusion Global Theme, or by the user): use it, like Plasma's own switch.
            if (s && (fusionPairing || !fusionCurrent) && s.darkModeFromPairing !== wantDark) {
                s.setDarkMode(wantDark);
                return;
            }
            // 2. A Plasma Fusion theme is active but not paired: switch to its twin.
            const target = wantDark ? backend.darkLookAndFeel : backend.lightLookAndFeel;
            const safe = target.replace(/[^A-Za-z0-9._-]/g, "");
            if (safe.length > 0) {
                backend.run("sh -c \"plasma-apply-lookandfeel --list | grep -qxF '" + safe + "' && plasma-apply-lookandfeel -a '" + safe + "'\"");
            }
        }
    }

    // ------------------------------------------------------------------ media
    readonly property var media: QtObject {
        readonly property var s: mediaLoader.item
        readonly property bool available: s ? s.available : false
        readonly property bool playing: s ? s.playing : false
        readonly property string title: s ? (s.track || s.identity) : ""
        readonly property string subtitle: {
            if (!s) {
                return "";
            }
            if (playing) {
                return s.artist || s.identity;
            }
            const paused = i18nc("@info:status media player", "Paused");
            return s.artist ? i18nc("@info:status %1 artist, %2 the word Paused", "%1 · %2", s.artist, paused) : paused;
        }
        readonly property string artUrl: s ? s.artUrl : ""
        readonly property string iconName: s ? s.iconName : ""
        readonly property bool canPrevious: s ? s.canPrevious : false
        readonly property bool canNext: s ? s.canNext : false
        readonly property bool canPlayPause: s ? s.canPlayPause : false
        readonly property bool canRaise: s ? s.canRaise : false
        readonly property var playersModel: s ? s.playersModel : null
        readonly property int currentIndex: s ? s.currentIndex : -1
        readonly property var player: s ? s.player : null
        readonly property bool canSeek: s ? s.canSeek : false
        readonly property double length: s ? s.length : 0
        readonly property double position: s ? s.position : 0
        function choosePlayer(i: int) { if (s) { s.choosePlayer(i); } }
        function seek(us: double) { if (s) { s.seek(us); } }
        function updatePosition() { if (s) { s.updatePosition(); } }
        function previous() {
            if (s) {
                s.previous();
            }
        }
        function next() {
            if (s) {
                s.next();
            }
        }
        function playPause() {
            if (s) {
                s.playPause();
            }
        }
        function raise() {
            if (s && s.canRaise) {
                s.raise();
                backend.closeRequested();
            }
        }
    }

    // ------------------------------------------------------------------ notifications
    readonly property var notif: QtObject {
        readonly property var s: notifLoader.item
        readonly property bool available: !!s && backend.showNotifications
        readonly property var model: s ? s.model : null
        readonly property int count: s ? s.count : 0
        readonly property int unread: s ? s.unread : 0
        // Rows come and go (services/Notifications.qml lastInGroup()).
        readonly property int revision: s ? s.revision : 0
        function lastInGroup(row: int, revision: int): bool {
            return s ? s.lastInGroup(row, revision) : false;
        }
        function setGroupExpanded(row: int, expanded: bool) {
            if (s) {
                s.setGroupExpanded(row, expanded);
            }
        }
        function collapseAllGroups() {
            if (s) {
                s.collapseAllGroups();
            }
        }
        function invokeAction(row: int, actionName: string, resident: bool) {
            if (s) {
                s.invokeAction(row, actionName, resident);
            }
        }
        function reply(row: int, text: string, resident: bool) {
            if (s) {
                s.reply(row, text, resident);
            }
        }
        function close(row: int) {
            if (s) {
                s.close(row);
            }
        }
        // Opens a file of the notification (its thumbnail, a finished job's file) and lets the
        // notification expire, as the stock applet does.
        function openUrl(row: int, url: string) {
            Qt.openUrlExternally(url);
            if (s) {
                s.expire(row);
            }
        }
        function configure(row: int) {
            if (s) {
                s.configure(row);
                backend.closeRequested();
            }
        }
        function killJob(row: int) {
            if (s) {
                s.killJob(row);
            }
        }
        function suspendJob(row: int) {
            if (s) {
                s.suspendJob(row);
            }
        }
        function resumeJob(row: int) {
            if (s) {
                s.resumeJob(row);
            }
        }
        // A finished job's folder: the one file selected in the file manager (`highlight`), or the
        // destination folder of several; the notification expires as after Open.
        function openFolder(row: int, url: string, highlight: bool) {
            if (!s) {
                return;
            }
            if (highlight) {
                s.showInFolder(url);
            } else {
                Qt.openUrlExternally(url);
            }
            s.expire(row);
        }
        function clearAll() {
            if (s) {
                s.clearAll();
            }
        }
        function markRead() {
            if (s) {
                s.markRead();
            }
        }
    }

    // ------------------------------------------------------------------ keyboard layout
    readonly property var kbd: QtObject {
        readonly property var s: kbdLoader.item
        readonly property bool available: s ? s.available : false
        readonly property int count: s ? s.count : 0
        readonly property string label: s ? s.label : ""
        readonly property string longName: s ? s.longName : ""
        readonly property var layouts: s ? s.layouts : []
        readonly property int index: s ? s.index : -1
        readonly property bool shown: backend.showKeyboardLayout && available && label.length > 0
                                      && (backend.keyboardLayoutAlways || count > 1)
        function next() {
            if (s) {
                s.next();
            }
        }
        function previous() {
            if (s) {
                s.previous();
            }
        }
        function select(i: int) {
            if (s) {
                s.select(i);
            }
        }
    }

    // ------------------------------------------------------------------ KDE Connect
    readonly property var phone: QtObject {
        readonly property var s: phoneLoader.item
        readonly property int connectedCount: s ? s.connectedCount : 0
        readonly property string deviceName: s ? s.deviceName : ""
        readonly property bool shown: backend.showKdeConnect && connectedCount > 0
        function open() {
            backend.run("sh -c 'kdeconnect-app >/dev/null 2>&1 &'");
            backend.closeRequested();
        }
    }

    // ------------------------------------------------------------------ bluetooth
    readonly property var bt: QtObject {
        readonly property var s: btLoader.item
        readonly property bool available: s ? s.available : false
        readonly property bool enabled: s ? s.powered : false
        readonly property bool blocked: s ? s.blocked : false
        // Clears a soft rfkill block, then calls done (at once when there is none, or no service).
        function unblock(done): void {
            if (s && s.blocked) {
                s.unblock(done);
            } else {
                done();
            }
        }
        readonly property int connectedCount: s ? s.connectedCount : 0
        readonly property var devicesModel: s ? s.devicesModel : null
        readonly property bool checked: available && enabled
        readonly property string subtitle: {
            if (!available) {
                return i18nc("@info:status Bluetooth", "Unavailable");
            }
            if (!enabled) {
                return i18nc("@info:status Bluetooth", "Off");
            }
            if (connectedCount === 1 && s.firstConnectedName) {
                return s.firstConnectedName;
            }
            if (connectedCount > 0) {
                return i18ncp("@info:status Bluetooth", "%1 connected", "%1 connected", connectedCount);
            }
            return i18nc("@info:status Bluetooth", "On");
        }
        function setEnabled(on: bool) {
            if (s) {
                s.setEnabled(on);
            }
        }
        function toggle() {
            if (s && available) {
                s.setEnabled(!enabled);
            }
        }
        function toggleDevice(device, ubi: string, connected: bool) {
            if (s) {
                s.toggleDevice(device, ubi, connected);
            }
        }
        function pairNew() {
            if (s) {
                s.pairNew();
                backend.closeRequested();
            }
        }
        function openSettings() {
            backend.openSettings("kcm_bluetooth", []);
        }
    }

    // ------------------------------------------------------------------ session / header buttons
    readonly property var session: QtObject {
        readonly property var s: sessionLoader.item
        readonly property bool canLock: s ? s.canLock : false
        function screenshot() {
            backend.closeRequested();
            screenshotTimer.restart();
        }
        // Copy text from the screen (survey F6): Spectacle's region capture, where Extract Text
        // copies the selected text, as the Meta+Shift+T key the setup gives the same command
        // (tools/device/fusion-config.sh, ensure_copytext_shortcut). Spectacle has no way to go
        // straight from a region to the text.
        function copyText() {
            backend.closeRequested();
            copyTextTimer.restart();
        }
        function openSystemSettings() {
            backend.openSettings("", []);
        }
        function lock() {
            backend.closeRequested();
            if (s) {
                s.lock();
            }
        }
        function leave() {
            backend.closeRequested();
            if (s) {
                s.leave();
            }
        }
    }

    // ------------------------------------------------------------------ clipboard
    // Each clipboard sheet opens on All, so the newest entry is current and Meta+V then Enter
    // chooses what was copied last. The Starred tab is the clipboard service's, which lives as long
    // as the widget, so it goes back to All when the page goes (the sheet closed, or back to quick
    // settings), before the next page is made: set by the new page itself, the tab bar's own index,
    // still Starred while it was built, wrote Starred back.
    onPageChanged: {
        if (page !== "clipboard" && clipboard.service) {
            clipboard.service.starredOnly = false;
        }
    }
    readonly property var clipboard: QtObject {
        readonly property var service: clipboardLoader.item
        readonly property bool available: !!service
        // Puts the entry on the clipboard and closes the sheet; the on-screen display says how to
        // paste it.
        function choose(uuid: string): void {
            if (!service) {
                return;
            }
            service.choose(uuid);
            backend.closeRequested();
            service.showPasteHint();
        }
        // Plasma's emoji selector (its own Meta+. shortcut action, else the program).
        function openEmoji(): void {
            backend.closeRequested();
            DBus.SessionBus.asyncCall({
                "service": "org.kde.kglobalaccel",
                "path": "/component/org_kde_plasma_emojier_desktop",
                "iface": "org.kde.kglobalaccel.Component",
                "member": "invokeShortcut",
                "arguments": [new DBus.string("_launch")],
                "signature": "(s)"
            }, () => {}, () => backend.run("plasma-emojier"));
        }
        function legacyPopup(): void {
            backend.closeRequested();
            backend.dbus("org.kde.klipper", "/klipper", "org.kde.klipper.klipper", "showKlipperPopupMenu", [], "");
        }
    }
    Timer {
        id: copyTextTimer
        // As for the screenshot: the pop-up closes first.
        interval: 250
        onTriggered: backend.run("sh -c 'spectacle --region >/dev/null 2>&1 &'")
    }
    Timer {
        id: screenshotTimer
        // Let the pop-up close first so it is not in the picture.
        interval: 250
        onTriggered: backend.dbus("org.kde.kglobalaccel", "/component/org_kde_spectacle_desktop", "org.kde.kglobalaccel.Component",
                                  "invokeShortcut", [new DBus.string("RectangularRegionScreenShot")], "(s)")
    }
}
