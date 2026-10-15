// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick

import "components"

// The rows of the notification history (NotificationEntry), for the sheet (PopupContent.qml) and the
// tablet Notification Centre: a Column, not a ListView. ListView ignores a size change of its first
// row while that row's add or displaced transition is scheduled or running (qquicklistview.cpp,
// QQuickListViewPrivate::itemGeometryChanged, Qt 6.11 and 6.12) and places the rows again only at the
// next change of the model. A new notification arrives on top and settles its height just after it is
// placed (its text wraps at the row's width), so the rows under it stayed where they were and were
// drawn over its bottom - a group's header over a card, a grouped card over the one before (owner
// report 2026-10-15). A positioner places its rows again after every size change, and its add and
// move transitions animate the same way. Every row exists anyway: the sheet's list is as tall as its
// content (the sheet scrolls), and the Centre lists the same history.
Column {
    id: list

    required property var notif
    required property FusionPalette pal
    required property FusionMetrics metrics
    required property Motion motion
    property double now: Date.now()
    property color surface: pal.overlay(0.06)
    property color edge: pal.overlay(0.08)
    property bool stackEdges: false
    property bool menus: false
    // A new row fades in (the sheet); the Centre's rows only slide.
    property bool fadeIn: true
    readonly property int count: rows.count

    signal done()
    signal menuRequested(Item card, point at, int index, var model)
    // A control of this row has keyboard focus (the sheet scrolls it into view).
    signal entryFocused(Item entry)

    Repeater {
        id: rows
        model: list.notif.available ? list.notif.model : null
        delegate: NotificationEntry {
            id: entryRow
            width: list.width
            pal: list.pal
            metrics: list.metrics
            notif: list.notif
            now: list.now
            surface: list.surface
            edge: list.edge
            stackEdges: list.stackEdges
            menus: list.menus
            onDone: list.done()
            onMenuRequested: (card, at) => list.menuRequested(card, at, entryRow.index, entryRow.model)
            onFocusInsideChanged: {
                if (focusInside) {
                    list.entryFocused(entryRow);
                }
            }
        }
    }

    // The rows there when the list is made appear as they are.
    populate: Transition {}
    add: Transition {
        enabled: list.motion.animate && list.fadeIn
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: list.motion.toggle }
    }
    // Rows moved by a row that arrives, goes or changes its height.
    move: Transition {
        enabled: list.motion.animate
        NumberAnimation { property: "y"; duration: list.motion.toggle; easing.type: list.motion.standardEasing }
    }
}
