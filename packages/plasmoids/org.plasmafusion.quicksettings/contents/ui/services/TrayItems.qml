// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.core as PlasmaCore

import "../../code/tray.js" as Tray

// Hidden tray items while they matter (P1, contents/code/tray.js): the stock vault, printer,
// display configuration and input-method items of the system tray in this widget's own panel
// are shown in the bar while active (an open vault, queued print jobs, presentation mode or a
// second screen, the input-method switch) and hidden again when passive, through the tray's
// shownItems. Their state is their own applet status (Plasma::Applet::status), read from the
// tray, so nothing here duplicates their logic, and their pop-ups are the stock ones.
Item {
    id: trayItems

    // The panel this widget is in (Plasmoid.containment), and the posture.
    property var containment: null
    property bool tablet: false
    // The widget was removed (Plasma::Applet::destroyed: the undo notification is shown, or the
    // panel is going). The tray's shownItems is the tray's own, kept in its configuration; nothing
    // else takes the items out again, so they are taken out here and the tray is let go. Undoing
    // the removal makes this false again.
    property bool removed: false

    // The system tray next to this widget, if any (Plasma 6.7: one applet that is also a
    // containment holding the items).
    readonly property var tray: {
        const applets = containment && !removed ? containment.applets : [];
        for (let i = 0; i < applets.length; ++i) {
            if (applets[i] && applets[i].pluginName === "org.kde.plasma.systemtray") {
                return applets[i];
            }
        }
        return null;
    }
    // [{id, active}] of the tray's items; reading each status makes this follow its changes.
    readonly property var items: {
        const applets = tray && tray.applets ? tray.applets : [];
        const out = [];
        for (let i = 0; i < applets.length; ++i) {
            const a = applets[i];
            if (!a) {
                continue;
            }
            const s = a.status;
            out.push({ id: a.pluginName, active: s === PlasmaCore.Types.ActiveStatus || s === PlasmaCore.Types.NeedsAttentionStatus
                                                 || s === PlasmaCore.Types.RequiresAttentionStatus });
        }
        return out;
    }
    readonly property int screens: Qt.application.screens.length
    readonly property var wanted: Tray.wanted(items, screens, tablet)
    // The ids this widget shows in the bar now (for the dump and the tests).
    property var revealed: []

    // The tray whose shownItems this widget last wrote: when the widget leaves it (moved to another
    // panel, the tray removed from this one, the widget removed), the items it showed there are
    // taken out, or they would stay in the bar for good.
    property QtObject managedTray: null

    onWantedChanged: Qt.callLater(apply)
    onTrayChanged: Qt.callLater(apply)
    // At once: a widget removed by desktop scripting (remove()) is deleted right after.
    onRemovedChanged: apply()
    function apply(): void {
        if (managedTray && managedTray !== tray) {
            update(managedTray.configuration, []);
        }
        managedTray = tray;
        const config = tray ? tray.configuration : null;
        revealed = config ? update(config, wanted) : [];
    }
    // Puts the wanted managed ids into a tray's shownItems and takes the others out; returns the
    // ids shown that way.
    function update(config: var, want: var): var {
        if (!config) {
            return [];
        }
        const list = key => {
            const v = config[key];
            return v === undefined || v === null || v === "" ? [] : (typeof v === "string" ? v.split(",") : Array.from(v, String));
        };
        const shown = list("shownItems");
        const disabled = list("disabledStatusNotifiers");
        const next = Tray.shownItems(shown, disabled, want);
        if (!Tray.same(shown, next)) {
            config.shownItems = next;
        }
        return Tray.MANAGED.filter(id => next.indexOf(id) !== -1 && disabled.indexOf(id) !== -1);
    }
}
