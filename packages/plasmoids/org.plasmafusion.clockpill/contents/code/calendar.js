/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

// What "Open calendar" (create false) and "Add event" (create true) do, given whether KOrganizer's
// D-Bus service can be started, whether a calendar application is installed and the name of the
// one the system uses (ApplicationIntegration.calendarApplicationName). KOrganizer is asked to go
// to the selected day only when it is that application, or for Add event (its editor); another
// calendar application opens directly, without the day (it has no such interface).
//   "korganizer-editor": go to the day in KOrganizer, then open its event editor
//   "korganizer-open":   go to the day in KOrganizer, then open the calendar application
//   "launch":            open the calendar application
//   "none":              nothing to open
function openAction(create, korganizerAvailable, calendarInstalled, calendarName) {
    const korganizerIsTheApp = /korganizer/i.test(String(calendarName || ""));
    if (korganizerAvailable && create) {
        return "korganizer-editor";
    }
    if (korganizerAvailable && korganizerIsTheApp) {
        return "korganizer-open";
    }
    return calendarInstalled ? "launch" : "none";
}
