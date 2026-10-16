// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.workspace.dbus as DBus

import "../../code/chips.js" as Chips

// The status items (StatusNotifierItem, over D-Bus) the chips stand in for, read as the tray reads
// them: xdg-desktop-portal-kde's "Screen casting" and "Remote Control" items (screencast.cpp,
// remotedesktop.cpp: one menu action, End) and Spectacle's recording item (SpectacleCore.cpp: the
// time in its tooltip, a click finishes the recording). The apps' messages are translated, so
// every pattern comes from the sending app's own catalogue (i18ndc with its domain), with a marker
// in place of the argument (Chips.argument). Other apps' items are read once and then left alone.
Item {
    id: statusItems

    // The portal's sessions: [{ key, kind: "screen" | "remote", app, window, input }].
    property var portal: []
    // Spectacle's recording, { key, time } (time as Spectacle shows it, "0:42"), or null.
    property var recording: null

    // "service/path" of every item this widget follows -> its last properties.
    property var known: ({})
    // Items of other apps, not followed.
    property var ignored: ({})
    // The reads under way, by registration: a reply that comes after its item unregistered is
    // dropped (Chips.readStarted).
    readonly property var reads: Chips.newReads()

    // Debug output for tests: QT_LOGGING_RULES="org.plasmafusion.livechips.debug=true".
    LoggingCategory {
        id: log
        name: "org.plasmafusion.livechips"
        defaultLogLevel: LoggingCategory.Warning
    }

    readonly property string marker: "\u0001"
    readonly property string castPattern: i18ndc("xdg-desktop-portal-kde", "@info:tooltip %1 the app that receives the screencast",
                                                  "Sharing contents to %1", marker)
    readonly property string remotePattern: i18ndc("xdg-desktop-portal-kde", "@info", "%1 is exercising remote control privileges:", marker)
    readonly property string remoteInputLine: i18ndc("xdg-desktop-portal-kde",
        "@info As in, 'an application is exercising privileges to control input devices'. '-' is Markdown, do not translate",
        "\n - Move the pointer and type keystrokes")
    readonly property string endLabel: i18ndc("xdg-desktop-portal-kde", "@action:inmenu stops screen/window sharing", "End")
    readonly property string recordingPattern: i18ndc("spectacle", "@info:tooltip subtitle for recording tray icon",
                                                      "Time recorded: %1\nClick to finish recording", marker)
    // Spectacle's item is known by its tooltip title (its id is Spectacle's translated name).
    readonly property var spectacleTitles: [
        i18ndc("spectacle", "@info:tooltip title for recording tray icon", "Spectacle is Recording"),
        i18ndc("spectacle", "@info:tooltip title for rendering tray icon", "Spectacle is Finishing the Recording")
    ]

    function str(value): string {
        return value === undefined || value === null ? "" : String(value);
    }
    function split(entry: string): var {
        const at = entry.indexOf("/");
        return at > 0 ? { service: entry.slice(0, at), path: entry.slice(at) } : null;
    }

    // ---- the watcher: every registered item, and each one that comes or goes
    function reload(): void {
        DBus.SessionBus.asyncCall({
            "service": "org.kde.StatusNotifierWatcher",
            "path": "/StatusNotifierWatcher",
            "iface": "org.freedesktop.DBus.Properties",
            "member": "Get",
            "arguments": [new DBus.string("org.kde.StatusNotifierWatcher"), new DBus.string("RegisteredStatusNotifierItems")],
            "signature": "(ss)"
        }, reply => {
            const list = (reply.value || []).map(v => statusItems.str(v));
            // Those followed, and those still being read.
            for (const key of Object.keys(statusItems.known).concat(Object.keys(statusItems.reads.live))) {
                if (list.indexOf(key) < 0) {
                    statusItems.forget(key);
                }
            }
            for (const key of list) {
                statusItems.read(key);
            }
        }, reply => console.debug(log, "livechips: no status notifier watcher (" + statusItems.str(reply.error && reply.error.message) + ")"));
    }
    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.kde.StatusNotifierWatcher"
        path: "/StatusNotifierWatcher"
        iface: "org.kde.StatusNotifierWatcher"
        function dbusStatusNotifierItemRegistered(entry) {
            statusItems.read(statusItems.str(entry));
        }
        function dbusStatusNotifierItemUnregistered(entry) {
            statusItems.forget(statusItems.str(entry));
        }
    }
    DBus.DBusServiceWatcher {
        busType: DBus.BusType.Session
        watchedService: "org.kde.StatusNotifierWatcher"
        onRegisteredChanged: if (registered) statusItems.reload()
    }
    Component.onCompleted: reload()

    // ---- one item: its properties, then (for the portal's and Spectacle's) a watch on its changes
    function read(key: string): void {
        const where = split(key);
        if (!where || ignored[key]) {
            return;
        }
        const token = Chips.readStarted(reads, key);
        DBus.SessionBus.asyncCall({
            "service": where.service,
            "path": where.path,
            "iface": "org.freedesktop.DBus.Properties",
            "member": "GetAll",
            "arguments": [new DBus.string("org.kde.StatusNotifierItem")],
            "signature": "(s)"
        }, reply => {
            if (Chips.readCurrent(statusItems.reads, key, token)) {
                statusItems.take(key, reply.value || {});
            }
        }, () => {
            if (Chips.readCurrent(statusItems.reads, key, token)) {
                statusItems.forget(key);
            }
        });
    }
    function take(key: string, props: var): void {
        const id = str(props.Id);
        const tip = props.ToolTip || [];
        const portalItem = id === "xdg-desktop-portal-kde";
        const spectacleItem = spectacleTitles.indexOf(str(tip[2])) >= 0;
        if (!portalItem && !spectacleItem) {
            const ignore = Object.assign({}, ignored);
            ignore[key] = true;
            ignored = ignore;
            return;
        }
        const entry = {
            key: key,
            id: portalItem ? id : "spectacle",
            icon: str(props.IconName),
            overlay: str(props.OverlayIconName),
            title: str(tip[2]),
            subtitle: str(tip[3]),
            menu: str(props.Menu)
        };
        const next = Object.assign({}, known);
        const isNew = !(key in next);
        next[key] = entry;
        known = next;
        if (isNew) {
            watched.append({ "key": key, "service": split(key).service, "path": split(key).path });
        }
        update();
    }
    function forget(key: string): void {
        Chips.readForgotten(reads, key);
        if (ignored[key]) {
            const ignore = Object.assign({}, ignored);
            delete ignore[key];
            ignored = ignore;
        }
        if (!(key in known)) {
            return;
        }
        const next = Object.assign({}, known);
        delete next[key];
        known = next;
        for (let i = 0; i < watched.count; ++i) {
            if (watched.get(i).key === key) {
                watched.remove(i);
                break;
            }
        }
        update();
    }
    ListModel {
        id: watched
    }
    Instantiator {
        model: watched
        delegate: DBus.SignalWatcher {
            required property string key
            required service
            required path
            busType: DBus.BusType.Session
            iface: "org.kde.StatusNotifierItem"
            function dbusNewToolTip() { statusItems.read(key); }
            function dbusNewIcon() { statusItems.read(key); }
            function dbusNewOverlayIcon() { statusItems.read(key); }
            function dbusNewTitle() { statusItems.read(key); }
            function dbusNewStatus(status) { statusItems.read(key); }
        }
    }

    // ---- what the chips show
    function update(): void {
        const sessions = [];
        let rec = null;
        for (const key of Object.keys(known)) {
            const e = known[key];
            if (e.id === "xdg-desktop-portal-kde") {
                const kind = Chips.portalKind(e.icon);
                if (kind === "screen") {
                    sessions.push({ key: key, kind: kind, app: Chips.argument(e.subtitle, castPattern, marker),
                                    window: e.overlay === "window", input: false });
                } else if (kind === "remote") {
                    const first = e.subtitle.split("\n")[0];
                    sessions.push({ key: key, kind: kind, app: Chips.argument(first, remotePattern, marker),
                                    window: false, input: e.subtitle.indexOf(remoteInputLine) >= 0 });
                }
            } else {
                // While it renders, the subtitle is another message (and a click would cut the
                // recording short): no recording chip then.
                const time = Chips.argument(e.subtitle, recordingPattern, marker);
                if (time !== "") {
                    rec = { key: key, time: time };
                }
            }
        }
        portal = sessions;
        recording = rec;
        console.debug(log, "livechips: status items " + JSON.stringify({ portal: sessions, recording: rec }));
    }

    // ---- actions
    // Spectacle: activating its item finishes the recording.
    function stopRecording(): void {
        const where = recording ? split(recording.key) : null;
        if (!where) {
            return;
        }
        console.debug(log, "livechips: finish the recording");
        DBus.SessionBus.asyncCall({
            "service": where.service, "path": where.path, "iface": "org.kde.StatusNotifierItem",
            "member": "Activate", "arguments": [new DBus.int32(0), new DBus.int32(0)], "signature": "(ii)"
        });
    }
    // The portal: its item's menu has one action, End (Session::close).
    function endSession(key: string): void {
        const e = known[key];
        const where = split(key);
        console.debug(log, "livechips: end " + key + " (menu " + (e ? e.menu : "?") + ")");
        if (!e || !where || e.menu === "" || e.menu === "/NO_DBUSMENU") {
            return;
        }
        const failed = what => reply => console.warn(log, "livechips: " + what + " failed for " + key + ": "
                                                      + statusItems.str(reply.error && reply.error.message));
        const menu = { "service": where.service, "path": e.menu, "iface": "com.canonical.dbusmenu" };
        DBus.SessionBus.asyncCall(Object.assign({ "member": "AboutToShow", "arguments": [new DBus.int32(0)], "signature": "(i)" }, menu), () => {
            DBus.SessionBus.asyncCall(Object.assign({
                "member": "GetLayout",
                "arguments": [new DBus.int32(0), new DBus.int32(-1), []],
                "signature": "(iias)"
            }, menu), reply => {
                const id = statusItems.endAction(reply.values ? reply.values[1] : null);
                console.debug(log, "livechips: end " + key + ": menu item " + id);
                if (id < 0) {
                    return;
                }
                DBus.SessionBus.asyncCall(Object.assign({
                    "member": "Event",
                    // The event's data is not read (libdbusmenu-qt); a string, as the D-Bus module
                    // marshals no other wrapped type inside a variant ("Unregistered type
                    // Plasma::DBus::INT32", seen in the session test).
                    "arguments": [new DBus.int32(id), new DBus.string("clicked"), new DBus.variant(""), new DBus.uint32(0)],
                    "signature": "(isvu)"
                }, menu), () => {}, failed("the menu's End"));
            }, failed("reading the menu"));
        }, failed("opening the menu"));
    }
    // The End entry of a dbusmenu layout ((id, properties, children)): by its label, else the one
    // action the menu has.
    function endAction(layout: var): int {
        const actions = [];
        function walk(node) {
            if (!node || node.length < 3) {
                return;
            }
            const props = node[1] || {};
            const kind = str(props["type"]);
            if (kind !== "separator" && props["enabled"] !== false && props["visible"] !== false && str(props["label"]) !== "") {
                actions.push({ id: Number(node[0]), label: str(props["label"]).replace(/[&_]/g, "") });
            }
            for (const child of (node[2] || [])) {
                walk(child);
            }
        }
        walk(layout);
        const labelled = actions.find(a => a.id > 0 && (a.label === endLabel.replace(/[&_]/g, "") || a.label === "End"));
        if (labelled) {
            return labelled.id;
        }
        const leaves = actions.filter(a => a.id > 0);
        return leaves.length === 1 ? leaves[0].id : -1;
    }
}
