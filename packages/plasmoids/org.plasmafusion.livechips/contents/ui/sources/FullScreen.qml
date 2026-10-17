// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.taskmanager as TaskManager

import "../../code/chips.js" as Chips

// Whether the screen is taken by a full-screen window (board Island.dc.html: the island shows only
// the privacy dots then): the last activated window on SCREEN that is not minimized is full screen
// (libtaskmanager's IsFullScreen role). Not the globally active window: with another screen's
// window focused, the full-screen one still covers this screen.
Item {
    id: fullScreen

    required property rect screenGeometry

    readonly property bool active: {
        void revision;
        const atm = TaskManager.AbstractTasksModel;
        const windows = [];
        for (let row = 0; row < tasks.rowCount(); ++row) {
            const index = tasks.index(row, 0);
            windows.push({ fullScreen: tasks.data(index, atm.IsFullScreen) === true, minimized: tasks.data(index, atm.IsMinimized) === true });
        }
        return Chips.fullScreenOf(windows);
    }
    property int revision: 0

    TaskManager.TasksModel {
        id: tasks
        filterByScreen: true
        screenGeometry: fullScreen.screenGeometry
        groupMode: TaskManager.TasksModel.GroupDisabled
        // The last activated first.
        sortMode: TaskManager.TasksModel.SortLastActivated
        onActiveTaskChanged: fullScreen.revision++
        onDataChanged: fullScreen.revision++
        onRowsInserted: fullScreen.revision++
        onRowsRemoved: fullScreen.revision++
        onRowsMoved: fullScreen.revision++
    }
}
