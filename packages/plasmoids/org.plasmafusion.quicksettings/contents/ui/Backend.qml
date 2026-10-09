// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus

import "components"
import "../code/power.js" as Power

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
    property string lightLookAndFeel: "org.plasmafusion.light.desktop"
    property string darkLookAndFeel: "org.plasmafusion.dark.desktop"
    // Page of the pop-up: "main", "wifi", "bluetooth", "audio", "power", "devices" or "display".
    property string page: "main"
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
        function setAirplaneMode(on: bool): void { if (s) { s.setAirplaneMode(on); } }
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
        readonly property string subtitle: {
            if (!active) {
                return i18nc("@info:status Do not disturb", "Off");
            }
            const until = s ? s.dndUntilText : "";
            return until ? i18nc("@info:status Do not disturb, %1 is a time", "Until %1", until)
                         : i18nc("@info:status Do not disturb", "On");
        }
        function toggle() {
            if (s) {
                s.toggleDnd();
            }
        }
        // G18: for one hour, or until tomorrow morning (06:00).
        function forHour() {
            if (s) {
                s.dndUntil(new Date(Date.now() + 3600 * 1000));
            }
        }
        function untilTomorrow() {
            if (s) {
                const d = new Date();
                d.setDate(d.getDate() + 1);
                d.setHours(6, 0, 0, 0);
                s.dndUntil(d);
            }
        }
        function openSettings() {
            backend.openSettings("kcm_notifications", []);
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
        // Why Performance is not offered or may be slower, and which applications hold a profile:
        // the stock Power and Battery widget's wording.
        readonly property string note: {
            const lines = [];
            switch (inhibitionReason) {
            case "":
                break;
            case "lap-detected":
                lines.push(i18nc("@info:tooltip", "Performance mode has been disabled to reduce heat generation because the computer has detected that it may be sitting on your lap."));
                break;
            case "high-operating-temperature":
                lines.push(i18nc("@info:tooltip", "Performance mode is unavailable because the computer is running too hot."));
                break;
            default:
                lines.push(i18nc("@info:tooltip", "Performance mode is unavailable."));
            }
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
        function cycle() {
            if (!s || !available) {
                backend.openSettings("kcm_powerdevilprofilesconfig", []);
                return;
            }
            // Performance is skipped while the daemon inhibits it; a refused switch shows on the tile.
            const next = Power.next(s.list, active, inhibitionReason);
            if (next !== "") {
                failedProfile = "";
                s.setProfile(next);
            }
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
        readonly property string subtitle: !available ? i18nc("@info:status Keep awake", "Unavailable")
                                         : active ? i18nc("@info:status Keep awake", "On")
                                                  : i18nc("@info:status Keep awake", "Off")
        function toggle(): void {
            if (s) {
                s.toggle(i18nc("@info reason for manual power inhibition", "Manually block sleep and screen locking"));
            }
        }
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
        function invokeAction(row: int, actionName: string, resident: bool) {
            if (s) {
                s.invokeAction(row, actionName, resident);
            }
        }
        function close(row: int) {
            if (s) {
                s.close(row);
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
        function openClipboard() {
            backend.closeRequested();
            backend.dbus("org.kde.klipper", "/klipper", "org.kde.klipper.klipper", "showKlipperPopupMenu", [], "");
        }
    }
    Timer {
        id: screenshotTimer
        // Let the pop-up close first so it is not in the picture.
        interval: 250
        onTriggered: backend.dbus("org.kde.kglobalaccel", "/component/org_kde_spectacle_desktop", "org.kde.kglobalaccel.Component",
                                  "invokeShortcut", [new DBus.string("RectangularRegionScreenShot")], "(s)")
    }
}
