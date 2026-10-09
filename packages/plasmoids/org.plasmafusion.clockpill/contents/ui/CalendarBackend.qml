// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.workspace.calendar as PlasmaCalendar
import org.kde.plasma.private.digitalclock
import org.kde.plasma.workspace.dbus as DBus

// Native calendar providers, shared with the stock clock and KDE PIM applications.
// Contract: plasma-workspace/components/calendar/{calendar,daysmodel,eventpluginsmanager}.h.
Item {
    id: backend

    property date displayedDate: new Date()
    property date selectedDate: displayedDate
    property date today: new Date()
    property int firstDayOfWeek: Qt.locale().firstDayOfWeek
    property var enabledPlugins: []

    property var days: []
    property var events: []
    property string actionError: ""
    property bool busy: false
    property bool korganizerAvailable: false
    readonly property string error: actionError || calendar.errorMessage
    readonly property bool calendarInstalled: ApplicationIntegration.calendarInstalled
    readonly property string calendarName: ApplicationIntegration.calendarApplicationName
    readonly property var providerModel: plugins.model
    readonly property var providerIds: {
        // The model property notifies after provider/config changes.
        const model = plugins.model;
        const role = model.KItemModels.KRoleNames.role("pluginId");
        const ids = [];
        for (let row = 0; row < model.rowCount(); ++row) {
            ids.push(String(model.data(model.index(row, 0), role)));
        }
        return ids;
    }
    readonly property bool configured: enabledPlugins.some(id => providerIds.indexOf(id) !== -1)

    function openCalendar(create: bool): void {
        if (busy) {
            return;
        }
        actionError = "";
        if (!korganizerAvailable) {
            if (calendarInstalled) {
                ApplicationIntegration.launchCalendar();
            }
            return;
        }
        busy = true;
        const dateText = Qt.locale().toString(selectedDate, Qt.locale().dateFormat(Locale.LongFormat));
        // Navigate the calendar, then open its native editor. KOrganizer chooses the draft's
        // default date/time from its current view; those fields remain editable in the editor.
        DBus.SessionBus.asyncCall({ service: "org.kde.korganizer", path: "/Calendar",
                    iface: "org.kde.Korganizer.Calendar", member: "goDate",
                    arguments: [new DBus.string(dateText)],
                    signature: "(s)" }, () => {
                        if (create) {
                            DBus.SessionBus.asyncCall({ service: "org.kde.korganizer", path: "/Calendar",
                                iface: "org.kde.Korganizer.Calendar", member: "openEventEditor" },
                                () => { backend.busy = false; }, reply => backend.actionFailed(reply));
                        } else {
                            ApplicationIntegration.launchCalendar();
                            backend.busy = false;
                        }
                    }, reply => backend.actionFailed(reply));
    }
    function actionFailed(reply): void {
        actionError = reply.error.message;
        busy = false;
    }
    function checkCalendarApp(): void {
        DBus.SessionBus.asyncCall({ service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus", member: "ListActivatableNames" }, reply => {
                backend.korganizerAvailable = Array.from(reply.value || []).indexOf("org.kde.korganizer") !== -1;
            }, () => { backend.korganizerAvailable = false; });
    }
    function refresh(): void {
        const model = calendar.daysModel;
        const roles = model.KItemModels.KRoleNames;
        const year = roles.role("yearNumber"), month = roles.role("monthNumber");
        const day = roles.role("dayNumber"), count = roles.role("eventCount");
        const next = [];
        for (let row = 0; row < model.rowCount(); ++row) {
            const index = model.index(row, 0);
            next.push({ year: model.data(index, year), month: model.data(index, month),
                        day: model.data(index, day), eventCount: model.data(index, count) });
        }
        days = next;
        // DaysModel caches its last agenda date. A data-ready signal can concern a future day
        // while agendaUpdated names today; querying another date first invalidates that cache.
        model.eventsForDate(new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate() + 1));
        events = model.eventsForDate(selectedDate);
    }
    onSelectedDateChanged: Qt.callLater(refresh)

    PlasmaCalendar.EventPluginsManager {
        id: plugins
        enabledPlugins: backend.enabledPlugins
    }
    PlasmaCalendar.Calendar {
        id: calendar
        days: 7
        weeks: 6
        displayedDate: backend.displayedDate
        today: backend.today
        firstDayOfWeek: backend.firstDayOfWeek
        Component.onCompleted: daysModel.setPluginsManager(plugins)
    }
    Connections {
        target: calendar.daysModel
        function onDataChanged() { Qt.callLater(backend.refresh); }
        function onModelReset() { Qt.callLater(backend.refresh); }
        function onRowsInserted() { Qt.callLater(backend.refresh); }
        function onRowsRemoved() { Qt.callLater(backend.refresh); }
        function onAgendaUpdated() { Qt.callLater(backend.refresh); }
    }
    Component.onCompleted: {
        Qt.callLater(refresh);
        checkCalendarApp();
    }
}
