// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts

import "../../code/chips.js" as Chips

// A timed Keep awake, as quick settings in the same bar keeps it: its widget's keepAwakeUntil (the
// end in ms since the epoch while a timed Keep awake runs, else 0), found as quick settings finds
// the pen menu (the panel's applet items). A click opens quick settings on its Keep awake page
// (openRequest "keepawake"). "Until turned off" has no chip: the status pill shows its cup.
Item {
    id: keepAwake

    // Debug output for tests: QT_LOGGING_RULES="org.plasmafusion.livechips.debug=true".
    LoggingCategory {
        id: log
        name: "org.plasmafusion.livechips"
        defaultLogLevel: LoggingCategory.Warning
    }

    // The applet whose bar this is (main.qml's root).
    required property Item appletRoot

    readonly property Item quickSettings: {
        let layout = appletRoot.parent;
        while (layout && !(layout instanceof GridLayout)) {
            layout = layout.parent;
        }
        if (!layout) {
            return null;
        }
        for (const child of layout.children) {
            // qmllint disable missing-property
            if (child.applet?.plasmoid?.pluginName === "org.plasmafusion.quicksettings") {
                return child.applet;
            }
            // qmllint enable missing-property
        }
        return null;
    }
    onQuickSettingsChanged: console.debug(log, "livechips: quick settings " + (quickSettings ? "found in the bar" : "not in the bar"))
    // qmllint disable missing-property
    readonly property double until: quickSettings && quickSettings.keepAwakeUntil > 0 ? quickSettings.keepAwakeUntil : 0
    // qmllint enable missing-property

    // The clock as last looked at: the time left follows it, once a minute.
    property double now: Date.now()
    readonly property var remaining: Chips.timeLeft(until, now)
    readonly property bool inUse: until > 0 && remaining.total > 0

    function open(): void {
        if (quickSettings) {
            console.debug(log, "livechips: open Keep awake in quick settings");
            // With the widget's own output: only the widget on KWin's active screen acts on a
            // request without one, and this bar may be on another screen.
            // qmllint disable missing-property
            const output = String(quickSettings.screenName || "");
            quickSettings.plasmoid.configuration.openRequest = "keepawake:" + Date.now() + (output !== "" ? ":" + output : "");
            // qmllint enable missing-property
        }
    }

    onUntilChanged: now = Date.now()
    Timer {
        // On the minute's turn of the time left, so the chip changes when the sheet's text does.
        interval: keepAwake.until > 0 ? Math.max(1000, (keepAwake.until - keepAwake.now) % 60000 || 60000) : 60000
        repeat: true
        running: keepAwake.until > 0
        onTriggered: keepAwake.now = Date.now()
    }
}
