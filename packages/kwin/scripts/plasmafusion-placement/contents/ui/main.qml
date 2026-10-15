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
// - A window is remembered while it floats (not maximized, full screen or tiled), once shortly
//   after it opens and where it was when it closes; a window opened maximized keeps its last
//   floating record. A window KWin holds in place (a window rule that forces its position) is
//   left to KWin: the script's geometry write would bypass the rule.
// - The memory lives in ~/.config/plasmafusion-placementrc [Windows] and is written and read
//   through plasmashell's desktop scripting: the KWin scripting API has no file write (only
//   readConfig). The file is read once at start (with a few retries while plasmashell comes up);
//   windows opened before that answer keep KWin's placement.
// - Settings (kwinrc [Script-plasmafusion-placement], contents/config/main.xml): RememberSize and
//   IgnoreApps (app ids or window classes). The KWin Scripts KCM writes them; KWin's reconfigure
//   reloads them in place.
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
            maximizeMode: w.maximizeMode,
            movable: w.moveable,
            resizable: w.resizeable
        };
    }

    function frameRect(w) {
        const g = w.frameGeometry;
        return { x: g.x, y: g.y, width: g.width, height: g.height };
    }

    function appIdOf(w) {
        return Placement.appId(String(w.resourceClass || ""), String(w.desktopFileName || ""));
    }

    // IgnoreApps is matched against the app id and the window class (Placement.identities).
    function ignoredWindow(w) {
        return Placement.ignored(Placement.identities(String(w.resourceClass || ""), String(w.desktopFileName || "")), ignoreList());
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

    // The desktop and activity views the pure guard takes (Placement.sameDesktop/sameActivity).
    function desktopView(w) {
        return { allDesktops: w.onAllDesktops, desktops: w.desktops };
    }
    function activityView(w) {
        return { activities: w.activities };
    }

    // The open windows of the same app on the same desktop and activity (the stack guard's input).
    function siblings(id, w) {
        const out = [];
        const windows = Workspace.stackingOrder;
        for (let i = 0; i < windows.length; ++i) {
            const o = windows[i];
            if (o === w || o.deleted || !o.normalWindow || appIdOf(o) !== id) {
                continue;
            }
            if (!Placement.sameDesktop(desktopView(w), desktopView(o)) || !Placement.sameActivity(activityView(w), activityView(o))) {
                continue;
            }
            out.push(frameRect(o));
        }
        return out;
    }

    // The callers decide whether the window may still be read: the close path records a window KWin
    // already marked deleted (its geometry and state stay readable for the close animation).
    function record(w, id) {
        if (!loaded || !w || ignoredWindow(w) || !Placement.eligible(stateOf(w))) {
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

    function windowOpened(w, restoreAllowed) {
        const key = String(w.internalId);
        if (watched[key]) {
            return;
        }
        const id = appIdOf(w);
        // held: KWin holds the window in place (a forced-position rule), taken now because an X11
        // window's rules are already dropped when it closes.
        const entry = { w: w, quietUntil: 0, settleSkip: false, held: w.moveable === false };
        const onGeometry = function () {
            root.geometryChanged(key);
        };
        entry.onGeometry = onGeometry;
        w.frameGeometryChanged.connect(onGeometry);
        watched[key] = entry;

        if (restoreAllowed && loaded && id !== "" && !ignoredWindow(w) && Placement.eligible(stateOf(w))) {
            const saved = apps[id];
            const current = frameRect(w);
            const screens = screenRects();
            const others = siblings(id, w);
            const rect = Placement.restoreFor(id, stateOf(w), saved, screens, others, ignoreList(), rememberSize(), current);
            if (rect) {
                entry.quietUntil = Date.now() + quietMillis;
                w.frameGeometry = Qt.rect(rect.x, rect.y, rect.width, rect.height);
                log("restored " + id + " to " + rect.x + "," + rect.y + " " + rect.width + "x" + rect.height);
            } else if (saved) {
                // Another instance of the app holds the spot: its record stays, and this window's
                // placement is not recorded as the new one - neither by the settling pass nor by
                // the window's own geometry changes while it opens (the quiet second, as after a
                // restore); the user's later moves are. (When the spot itself is unusable - off a
                // screen - the settle pass heals the record to where KWin placed it.)
                const finalRect = Placement.restoreRect(saved, current, Placement.restoreSize(stateOf(w), rememberSize()));
                if (Placement.onScreen(finalRect, screens) && Placement.collides(finalRect, others)) {
                    entry.settleSkip = true;
                    entry.quietUntil = Date.now() + quietMillis;
                }
            }
        }
        // An adopted window is not settled: the user has not touched it, and recording every open
        // window when the script loads would replace the records they left (the last window of an
        // app in stacking order winning). Its moves and its close record it.
        if (restoreAllowed) {
            settling.push(w);
            settle.restart();
        }
    }

    function windowClosed(w) {
        const key = String(w.internalId);
        const entry = watched[key];
        if (!entry) {
            return;
        }
        // The last place before the window went. KWin marks a closing window deleted before
        // windowRemoved (Wayland and X11), so the window is read as it is: its frame geometry,
        // maximize mode and tile stay as they were (requestTile is a no-op once deleted).
        if (loaded && !entry.held && Date.now() >= entry.quietUntil) {
            record(w, appIdOf(w));
        }
        if (entry.onGeometry) {
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
            root.windowOpened(w, true);
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
        // Windows already open when the script (re)loads - a Fusion setup enables it in a running
        // session, a reconfigure can reload it - are watched so their moves and closes are
        // remembered; they are never moved by the script itself (KWin placed them already) and not
        // recorded until the user moves or closes them.
        const windows = Workspace.stackingOrder;
        let adopted = 0;
        for (let i = 0; i < windows.length; ++i) {
            const w = windows[i];
            if (!w || w.deleted || !w.normalWindow || w.transient || w.modal) {
                continue;
            }
            if (!watched[String(w.internalId)]) {
                windowOpened(w, false);
                adopted++;
            }
        }
        if (adopted > 0) {
            log("adopted " + adopted + " open window(s)");
        }
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
