/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kwin
import "Workspaces.js" as Workspaces

// Plasma Fusion dynamic workspaces (bug 446448), off until the user turns it on: workspaces come and
// go as windows need them, the way GNOME does it. There is always one empty workspace at the end -
// move a window there, or open one on it, and the next empty one appears - and an empty workspace
// goes once nothing shows it. The top bar's workspace dots (and the pager) follow KWin's desktops
// as they are.
//
// - Kept: a workspace with a window of the user's (every activity counts: KWin's desktops are
//   shared by the activities), the empty one after the last occupied workspace, the one each screen
//   shows, and the first KeepFirst workspaces (kwinrc [Script-plasmafusion-workspaces], 0-24,
//   default 0). Workspaces.js holds the rules.
// - Timing: nothing changes until a second after a desktop switch (KWin's slide effect ends its
//   animation at once when a desktop is added or removed); removals also wait a second after a
//   window closes and ten seconds after the script starts (a session restore brings windows back
//   to their desktops by id).
// - A workspace the script adds is called "Workspace N" for its position, and after removals those
//   names follow their positions. No other name is ever changed (Fusion's Work, Design, Media and
//   Chat, the user's own, KWin's "Desktop N").
//
// No timer runs while idle: one shot per burst of changes.
Item {
    id: root

    property real startedAt: 0
    property real lastSwitchAt: -Infinity
    property real lastCloseAt: -Infinity
    // internalId -> {w, onChange}: the windows whose desktop moves are watched.
    property var watched: ({})

    function log(message) {
        console.info("plasmafusion-workspaces: " + message);
    }

    function keepFirst() {
        return KWin.readConfig("KeepFirst", 0);
    }

    // The script's numbered names, translated: numbered[i] is the name of number i + 1.
    function numberedNames() {
        const out = [];
        for (let n = 1; n <= 25; ++n) {
            out.push(i18ndc("plasmafusion", "@title name of a workspace the dynamic workspaces add, %1 its number", "Workspace %1", n));
        }
        return out;
    }

    function idsOf(desktops) {
        const out = [];
        for (let i = 0; i < desktops.length; ++i) {
            out.push(String(desktops[i].id));
        }
        return out;
    }

    function windowView(w) {
        return {
            managed: w.managed,
            deleted: w.deleted,
            allDesktops: w.onAllDesktops,
            skipPager: w.skipPager,
            special: w.specialWindow,
            popup: w.popupWindow,
            desktops: idsOf(w.desktops || [])
        };
    }

    // The desktop each screen shows (per-screen desktops give every screen its own), and the
    // workspace's current one.
    function currentIds() {
        const out = [];
        if (Workspace.currentDesktop) {
            out.push(String(Workspace.currentDesktop.id));
        }
        const screens = Workspace.screens;
        for (let i = 0; i < screens.length; ++i) {
            const d = Workspace.currentDesktopForScreen(screens[i]);
            if (d) {
                out.push(String(d.id));
            }
        }
        return out;
    }

    // ---------------------------------------------------------------- the pass

    function schedule(delay) {
        const wait = Math.max(0, delay || 0);
        if (!pass.running || wait < pass.interval) {
            pass.interval = wait;
            pass.restart();
        }
    }

    Timer {
        id: pass
        interval: 0
        onTriggered: root.update()
    }

    // One pass: read the desktops and windows, decide, carry it out. KWin's own signals from the
    // changes made here only schedule another pass (which then finds nothing to do).
    function update() {
        const desktops = Workspace.desktops;
        const ids = idsOf(desktops);
        const windows = Workspace.windows;
        const views = [];
        for (let i = 0; i < windows.length; ++i) {
            views.push(windowView(windows[i]));
        }
        const occupied = Workspaces.occupancy(ids, views);
        const wanted = Workspaces.plan(ids, occupied, currentIds(), keepFirst());
        const now = Date.now();
        const decision = Workspaces.decide(wanted, {
            now: now,
            started: startedAt,
            lastSwitch: lastSwitchAt,
            lastClose: lastCloseAt
        });
        const since = (lastSwitchAt === -Infinity ? "no switch yet" : Math.round(now - lastSwitchAt) + " ms after the last switch")
            + ", " + (lastCloseAt === -Infinity ? "no close yet" : Math.round(now - lastCloseAt) + " ms after the last close");

        for (let i = 0; i < decision.remove.length; ++i) {
            const index = ids.indexOf(decision.remove[i]);
            if (index < 0) {
                continue;
            }
            const desktop = desktops[index];
            log("removed empty workspace \"" + desktop.name + "\" at position " + (index + 1) + " (" + since + ")");
            Workspace.removeDesktop(desktop);
        }

        const numbered = numberedNames();
        if (decision.append) {
            const count = Workspace.desktops.length;
            if (Workspaces.canAdd(count)) {
                const name = Workspaces.nameFor(count, numbered);
                Workspace.createDesktop(count, name);
                log("added workspace \"" + name + "\" at position " + (count + 1) + " (" + since + ")");
            }
        }

        const after = Workspace.desktops;
        const current = [];
        for (let i = 0; i < after.length; ++i) {
            current.push({ id: String(after[i].id), name: String(after[i].name) });
        }
        const changes = Workspaces.renames(current, numbered);
        const afterIds = idsOf(after);
        for (let i = 0; i < changes.length; ++i) {
            const index = afterIds.indexOf(changes[i].id);
            if (index >= 0) {
                log("renamed workspace \"" + after[index].name + "\" to \"" + changes[i].name + "\"");
                after[index].name = changes[i].name;
            }
        }

        if (decision.retryIn >= 0) {
            schedule(decision.retryIn);
        }
    }

    // ---------------------------------------------------------------- windows

    // Only windows of the kind that can hold a desktop are watched (Workspaces.candidate); tooltips
    // and popups come and go all the time and never change a desktop's state.
    function watch(w) {
        if (!w || w.deleted || !Workspaces.candidate(windowView(w))) {
            return false;
        }
        const key = String(w.internalId);
        if (watched[key]) {
            return true;
        }
        const onChange = function () {
            root.schedule(0);
        };
        w.desktopsChanged.connect(onChange);
        w.skipPagerChanged.connect(onChange);
        watched[key] = { w: w, onChange: onChange };
        return true;
    }

    // A watched window closed: true when it held its desktops right before (KWin marks a closing
    // window deleted before windowRemoved; everything else about it still reads as it was).
    function unwatch(w) {
        const key = String(w.internalId);
        const entry = watched[key];
        if (!entry) {
            return false;
        }
        w.desktopsChanged.disconnect(entry.onChange);
        w.skipPagerChanged.disconnect(entry.onChange);
        delete watched[key];
        const view = windowView(w);
        view.deleted = false;
        return Workspaces.counts(view);
    }

    Connections {
        target: Workspace
        function onWindowAdded(w) {
            if (root.watch(w)) {
                root.schedule(0);
            }
        }
        // The grace after a close (a dialog handing over to its app's next window) starts only when
        // the window held its desktop.
        function onWindowRemoved(w) {
            if (w && root.unwatch(w)) {
                root.lastCloseAt = Date.now();
                root.schedule(0);
            }
        }
        function onCurrentDesktopChanged() {
            root.lastSwitchAt = Date.now();
            root.schedule(0);
        }
        function onDesktopsChanged() {
            root.schedule(0);
        }
        function onScreensChanged() {
            root.schedule(0);
        }
    }

    // A reconfigure (the KWin Scripts page applying KeepFirst) re-reads the settings: one pass with
    // the new value.
    Connections {
        target: Options
        function onConfigChanged() {
            root.schedule(0);
        }
    }

    // ---------------------------------------------------------------- start and stop

    Component.onCompleted: {
        startedAt = Date.now();
        const windows = Workspace.windows;
        for (let i = 0; i < windows.length; ++i) {
            watch(windows[i]);
        }
        log("started (" + Workspace.desktops.length + " workspace(s), keeping the first " + Workspaces.keepCount(keepFirst()) + ")");
        schedule(0);
    }

    // Disabled or KWin going away: KWin keeps one QML engine for its scripts and the windows outlive
    // this object, so a handler left connected would call into a destroyed context (and every
    // disable/enable cycle would add another).
    Component.onDestruction: {
        pass.stop();
        for (const key in watched) {
            const entry = watched[key];
            if (entry.w) {
                entry.w.desktopsChanged.disconnect(entry.onChange);
                entry.w.skipPagerChanged.disconnect(entry.onChange);
            }
        }
        watched = {};
    }
}
