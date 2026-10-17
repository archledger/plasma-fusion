// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.taskmanager as TaskManager

// Whether the active window on SCREEN is full screen (board Island.dc.html: the island shows only
// the privacy dots then): the task manager's active task among the windows on that screen
// (libtaskmanager's IsFullScreen role).
Item {
    id: fullScreen

    required property rect screenGeometry

    readonly property bool active: {
        void revision;
        const index = tasks.activeTask;
        return index && index.valid ? tasks.data(index, TaskManager.AbstractTasksModel.IsFullScreen) === true : false;
    }
    property int revision: 0

    TaskManager.TasksModel {
        id: tasks
        filterByScreen: true
        screenGeometry: fullScreen.screenGeometry
        groupMode: TaskManager.TasksModel.GroupDisabled
        onActiveTaskChanged: fullScreen.revision++
        onDataChanged: fullScreen.revision++
    }
}
