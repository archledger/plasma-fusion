/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kwin
import "Placement.js" as Placement

// Plasma Fusion window placement memory (bug 15329 - the desktop's most-duplicated open wish):
// each app's window is remembered where and how big it was left, and given back when the app
// opens again, like Windows and macOS do. A record only applies while its centre still lies on a
// screen the session has; a spot on a monitor that is gone is left to KWin's placement.
//
// - One record per app: its desktop file (stable across Wayland and X11), else the window class.
//   Several windows of one app share the record - the one the user moves (or closes) last sets
//   it, and a new window is not stacked exactly on the remembered spot when an instance of the
//   app already holds it (KWin's own placement then offsets it, and that record stays).
// - A window is remembered while it floats (not maximized, full screen or tiled) and once shortly
//   after it opens; a window opened maximized keeps its last floating record.
// - The memory lives in ~/.config/plasmafusion-placementrc [Windows] and is written and read
//   through plasmashell's desktop scripting: the KWin scripting API has no file write (only
//   readConfig). The file is read once at start (with a few retries while plasmashell comes up);
//   windows opened before that answer keep KWin's placement.
// - Settings (kwinrc [Script-plasmafusion-placement], contents/config/main.xml): RememberSize and
//   IgnoreApps. The KWin Scripts KCM writes them; KWin's reconfigure reloads them in place.
//
// No timer runs while idle: one shot per window open, one for a pending memory write.
Item {
    id: root

    // ---------------------------------------------------------------- memory state

    // app id -> {x, y, width, height}: the memory file's [Windows] group, one JSON entry.
    property var apps: ({})
    property bool loaded: false
    property int revision: 0 // bumped by every memory change
    property int sentRevision: 0 // the revision the last write carried
    property int sendingRevision: -1
    property bool sending: false
    property int readTries: 0
    // How long after an open the memory ignores geometry changes: the restore itself and an app's
    // own late repositioning must not churn the record before the window settles.
    readonly property int quietMillis: 1000

    readonly property string memoryFile: "plasmafusion-placementrc"
    readonly property string memoryGroup: "Windows"
    readonly property string memoryKey: "windows"

    function log(message) {
        console.info("plasmafusion-placement: " + message);
    }

    // ---------------------------------------------------------------- settings

    function setting(key, fallback) {
        const value = KWin.readConfig(key, fallback);
        if (typeof fallback === "boolean") {
            return value === true || value === "true";
        }
        return value === undefined || value === null ? fallback : String(value);
    }
    function rememberSize() {
        return setting("RememberSize", true);
    }
    function ignoreList() {
        return setting("IgnoreApps", "");
    }

    // ---------------------------------------------------------------- the memory file
    // Both directions run through plasmashell's desktop scripting: evaluateScript answers with
    // what the script printed, and a ConfigFile write is synced when the scripting engine drops
    // the object at the end of the call.

    function readScript() {
        return "var out = '';\n"
            + "try {\n"
            + "    var c = ConfigFile('" + memoryFile + "', '" + memoryGroup + "');\n"
            + "    var v = c.readEntry('" + memoryKey + "');\n"
            + "    if (typeof v === 'string') { out = v; }\n"
            + "} catch (e) {}\n"
            + "print(out);";
    }

    function writeScript(text) {
        return "var c = ConfigFile('" + memoryFile + "', '" + memoryGroup + "');\n"
            + "c.writeEntry('" + memoryKey + "', " + JSON.stringify(text) + ");";
    }

    function read() {
        if (loaded) {
            return;
        }
        readTries++;
        readCall.arguments = [readScript()];
        readCall.call();
    }

    function readDone(text) {
        if (loaded) {
            return;
        }
        apps = Placement.parse(text);
        loaded = true;
        log("memory loaded: " + Object.keys(apps).length + " app(s)");
    }

    DBusCall {
        id: readCall
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: returnValue => root.readDone(returnValue.length > 0 ? String(returnValue[0]) : "")
        onFailed: {
            if (root.readTries < 10) {
                readRetry.start();
            } else {
                root.log("plasmashell did not answer; this session runs without the window memory");
            }
        }
    }

    Timer {
        id: readRetry
        interval: 2000
        onTriggered: root.read()
    }

    function write() {
        if (!loaded || sending || sentRevision === revision) {
            return;
        }
        sending = true;
        sendingRevision = revision;
        writeCall.arguments = [writeScript(Placement.serialize(apps))];
        writeCall.call();
    }

    DBusCall {
        id: writeCall
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: {
            root.sending = false;
            root.sentRevision = root.sendingRevision;
            if (root.revision !== root.sentRevision) {
                flush.interval = 2000;
                flush.restart();
            }
        }
        onFailed: {
            root.sending = false;
            root.log("the memory file could not be written (plasmashell down?); trying again shortly");
            flush.interval = 15000;
            flush.restart();
        }
    }

    Timer {
        id: flush
        interval: 2000
        onTriggered: root.write()
    }

    function changed() {
        revision++;
        if (!sending) {
            flush.interval = 2000;
            flush.restart();
        }
    }

    // ---------------------------------------------------------------- windows

    // internalId -> {w, onGeometry, quietUntil, settleSkip}: every ordinary window under watch.
    property var watched: ({})
    // Windows whose settling pass is still due (compared by identity).
    property var settling: []

    function stateOf(w) {
        return {
            normal: w.normalWindow,
            transient: w.transient,
            modal: w.modal,
            fullScreen: w.fullScreen,
            tiled: !!w.tile,
            minimized: w.minimized,
            maximizeMode: w.maximizeMode
        };
    }

    function frameRect(w) {
        const g = w.frameGeometry;
        return { x: g.x, y: g.y, width: g.width, height: g.height };
    }

    function appIdOf(w) {
        return Placement.appId(String(w.resourceClass || ""), String(w.desktopFileName || ""));
    }

    function screenRects() {
        const out = [];
        const screens = Workspace.screens;
        for (let i = 0; i < screens.length; ++i) {
            const g = screens[i].geometry;
            out.push({ x: g.x, y: g.y, width: g.width, height: g.height });
        }
        return out;
    }

    // The desktop view the pure guard takes (Placement.sameDesktop).
    function desktopView(w) {
        return { allDesktops: w.onAllDesktops, desktops: w.desktops };
    }

    // The open windows of the same app on the same desktop (the stack guard's input).
    function siblings(id, w) {
        const out = [];
        const windows = Workspace.stackingOrder;
        for (let i = 0; i < windows.length; ++i) {
            const o = windows[i];
            if (o === w || o.deleted || !o.normalWindow || appIdOf(o) !== id) {
                continue;
            }
            if (!Placement.sameDesktop(desktopView(w), desktopView(o))) {
                continue;
            }
            out.push(frameRect(o));
        }
        return out;
    }

    function record(w, id) {
        if (!loaded || !w || w.deleted || Placement.ignored(id, ignoreList()) || !Placement.eligible(stateOf(w))) {
            return;
        }
        if (Placement.remember(apps, id, frameRect(w))) {
            changed();
        }
    }

    // A geometry change the memory was told about (never during the quiet window after a restore;
    // the settling pass reads the window then instead).
    function geometryChanged(key) {
        const entry = watched[key];
        if (!entry || !loaded || !entry.w || entry.w.deleted || Date.now() < entry.quietUntil) {
            return;
        }
        record(entry.w, appIdOf(entry.w));
    }

    function windowOpened(w) {
        const key = String(w.internalId);
        if (watched[key]) {
            return;
        }
        const id = appIdOf(w);
        const entry = { w: w, quietUntil: 0, settleSkip: false };
        const onGeometry = function () {
            root.geometryChanged(key);
        };
        entry.onGeometry = onGeometry;
        w.frameGeometryChanged.connect(onGeometry);
        watched[key] = entry;

        if (loaded && !Placement.ignored(id, ignoreList()) && Placement.eligible(stateOf(w))) {
            const saved = apps[id];
            const screens = screenRects();
            const others = siblings(id, w);
            const rect = Placement.restoreFor(id, stateOf(w), saved, screens, others, ignoreList(), rememberSize(), frameRect(w));
            if (rect) {
                entry.quietUntil = Date.now() + quietMillis;
                w.frameGeometry = Qt.rect(rect.x, rect.y, rect.width, rect.height);
                log("restored " + id + " to " + rect.x + "," + rect.y + " " + rect.width + "x" + rect.height);
            } else if (saved && Placement.onScreen(saved, screens) && Placement.collides(saved, others)) {
                // Another instance of the app holds the remembered spot: its record stays, and so
                // does this window's placement (the user's own moves are remembered from here).
                entry.settleSkip = true;
            }
        }
        settling.push(w);
        settle.restart();
    }

    function windowClosed(w) {
        const key = String(w.internalId);
        const entry = watched[key];
        if (!entry) {
            return;
        }
        if (!w.deleted && loaded && Date.now() >= entry.quietUntil) {
            record(w, appIdOf(w)); // the last place before the window went
        }
        if (entry.onGeometry && !w.deleted) {
            w.frameGeometryChanged.disconnect(entry.onGeometry);
        }
        delete watched[key];
    }

    Connections {
        target: Workspace
        function onWindowAdded(w) {
            if (!w || w.deleted || !w.normalWindow || w.transient || w.modal) {
                return;
            }
            root.windowOpened(w);
        }
        function onWindowRemoved(w) {
            if (w) {
                root.windowClosed(w);
            }
        }
    }

    // The settling pass: what a window's geometry is shortly after it opens is the record (the
    // restored spot unless the app moved itself again). One shot per burst of opens.
    Timer {
        id: settle
        interval: 1000
        onTriggered: {
            const list = root.settling;
            root.settling = [];
            for (let i = 0; i < list.length; ++i) {
                const w = list[i];
                if (!w || w.deleted) {
                    continue;
                }
                const entry = root.watched[String(w.internalId)];
                if (!entry || entry.settleSkip) {
                    continue;
                }
                root.record(w, root.appIdOf(w));
            }
        }
    }

    // ---------------------------------------------------------------- start and stop

    Component.onCompleted: {
        log("started");
        read();
    }

    // Disabled or KWin going away: the pending record goes out one last time, best effort (the
    // D-Bus message is on its way before the object dies).
    Component.onDestruction: {
        if (loaded && revision !== sentRevision && !sending) {
            writeCall.arguments = [writeScript(Placement.serialize(apps))];
            writeCall.call();
        }
    }
}
