// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick

import "components"

// The rows of the sheet's notification history (NotificationEntry, PopupContent.qml): a Column, not
// a ListView with transitions. ListView ignores a size change of its first row while that row's add
// or displaced transition is scheduled or running (qquicklistview.cpp,
// QQuickListViewPrivate::itemGeometryChanged, Qt 6.11 and 6.12) and places the rows again only at
// the next change of the model. A new notification arrives on top and settles its height just after
// it is placed (its text wraps at the row's width), so the rows under it stayed where they were and
// were drawn over its bottom - a group's header over a card, a grouped card over the one before
// (owner report 2026-10-15). A positioner places its rows again after every size change, and its
// add and move transitions animate the same way. Every row existed before as well: the sheet's list
// is as tall as its content and the sheet's Flickable scrolls it. (The tablet Notification Centre
// scrolls a long history itself, so it keeps a virtualised ListView, without view transitions.)
Column {
    id: list

    required property var notif
    required property FusionPalette pal
    required property FusionMetrics metrics
    required property Motion motion
    property double now: Date.now()
    // The card menu (a long press, a right click, the Menu key on a card).
    property bool menus: false
    readonly property int count: rows.count

    signal done()
    signal menuRequested(Item card, point at)
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
            menus: list.menus
            onDone: list.done()
            onMenuRequested: (card, at) => list.menuRequested(card, at)
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
        enabled: list.motion.animate
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: list.motion.toggle }
    }
    // Rows moved by a row that arrives, goes or changes its height.
    move: Transition {
        enabled: list.motion.animate
        NumberAnimation { property: "y"; duration: list.motion.toggle; easing.type: list.motion.standardEasing }
    }
}
