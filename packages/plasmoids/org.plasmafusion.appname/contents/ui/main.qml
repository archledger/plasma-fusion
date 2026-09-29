/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.plasma.workspace.dbus as DBus

// Top-left of the Plasma Fusion top bar (Main / MainLight boards): a 32x26 button with the
// Fusion logo that opens the launcher, then the active application's name in Manrope 13 px
// ExtraBold ("Desktop" when no window is focused). The global menu is the stock
// org.kde.plasma.appmenu widget placed after this one.
//
// The widget has no pop-up: everything is shown directly in the panel.
PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // Board geometry (px): header padding-left 10, button 32x26 radius 8, gap 2, name padding
    // 0 10 0 6. `startPadding` makes up the difference between the panel's own left margin and
    // the board's 10 px, so that the button lands at x = 10 in a Plasma Fusion top bar.
    readonly property int startPadding: Plasmoid.configuration.startPadding
    readonly property int buttonWidth: 32
    readonly property int buttonHeight: 26
    readonly property int nameGap: 2 + 6
    readonly property int nameEndPadding: Plasmoid.configuration.endPadding
    readonly property int nameMaxWidth: Plasmoid.configuration.maximumNameWidth

    // Colours follow the colour scheme: dark boards use white tints, light boards the text ink.
    readonly property bool dark: {
        const c = Kirigami.Theme.backgroundColor;
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
    }
    readonly property color ink: dark ? "#ffffff" : Kirigami.Theme.textColor
    readonly property color focusColor: dark ? "#8ab8ff" : "#2f6fdf"
    function tint(alpha: real): color {
        return Qt.rgba(ink.r, ink.g, ink.b, alpha);
    }

    // Name of the active application, "" while no window is active.
    property string appName: ""
    readonly property string shownName: appName !== ""
        ? appName
        : i18nc("@label top bar title when no window is focused", "Desktop")

    // The board draws the logo button filled while the launcher is open. The launcher lives in
    // another panel, so its state cannot be read; it is followed through window focus instead:
    // a toggle request (this button, its shortcut, or the shell's "Activate Application
    // Launcher" action on Alt+F1) flips the state and expects one focus change as its result
    // (the launcher taking focus, or giving it back). Any later focus change means the launcher
    // closed by itself (Esc, Meta, a click outside, an application started), also when the focus
    // goes back to the desktop and no application window becomes active. The Meta key reaches
    // the shell through KWin directly, so a launcher opened with it does not light the button.
    // TasksModel reports activation changes of every window, the shell's own included, through
    // activeTaskChanged, even when the active task itself stays invalid.
    property bool launcherOpen: false
    property bool requestPending: false
    // activeTaskChanged signals in the current burst. A focus change sends at least two (one
    // window loses the focus, another gets it); one alone is a window of the shell going away
    // (a tooltip, a notification) and says nothing about the launcher.
    property int focusSignals: 0

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: ""
    toolTipSubText: ""

    Layout.minimumWidth: vertical ? -1 : row.implicitWidth
    Layout.preferredWidth: vertical ? -1 : row.implicitWidth
    Layout.maximumWidth: vertical ? Infinity : row.implicitWidth
    Layout.minimumHeight: vertical ? buttonHeight : -1
    Layout.preferredHeight: vertical ? buttonHeight : -1
    Layout.maximumHeight: vertical ? buttonHeight : Infinity

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action:inmenu", "Open Launcher")
            icon.name: "start-here-kde-symbolic"
            onTriggered: root.openLauncher()
        }
    ]

    // The shell's "Activate Application Launcher" action: it toggles the first launcher widget
    // (X-Plasma-Provides org.kde.plasma.launchermenu: the Plasma Fusion launcher, or Kickoff)
    // in a panel of the active screen, exactly as the Meta key does.
    function openLauncher() {
        noteLauncherToggle();
        DBus.SessionBus.asyncCall({
            "service": "org.kde.plasmashell",
            "path": "/PlasmaShell",
            "iface": "org.kde.PlasmaShell",
            "member": "activateLauncherMenu",
            "arguments": []
        }, () => {}, () => {
            root.launcherOpen = false;
            root.requestPending = false;
        });
    }

    // A toggle of the launcher was requested: flip the shown state and wait for its result.
    function noteLauncherToggle() {
        launcherOpen = !launcherOpen;
        requestPending = true;
        // A focus change noticed just before the request is not its result.
        focusSettle.stop();
        focusSignals = 0;
        requestTimeout.restart();
    }

    // A burst of focus changes has settled.
    function focusMoved() {
        const signals = focusSignals;
        focusSignals = 0;
        if (tasksModel.activeTask.valid || Application.state !== Qt.ApplicationActive) {
            // An application window is active, or no shell window is: the launcher is closed.
            launcherOpen = false;
            requestPending = false;
        } else if (signals < 2) {
            // No focus change.
            return;
        } else if (requestPending) {
            // The result of the last request (the launcher opened or closed).
            requestPending = false;
        } else {
            // The shell's focus moved without a request: the launcher closed by itself.
            launcherOpen = false;
        }
    }

    // Folds the several activation signals of one focus change into one.
    Timer {
        id: focusSettle
        interval: 200
        onTriggered: root.focusMoved()
    }

    // A request that caused no focus change within this time (no launcher, or it failed to
    // open) no longer waits for one.
    Timer {
        id: requestTimeout
        interval: 3000
        onTriggered: root.requestPending = false
    }

    // The shell's own launcher action (its Alt+F1 shortcut): the same toggle, requested elsewhere.
    readonly property QtObject launcherAction: {
        const containment = Plasmoid.containment;
        const corona = containment ? containment.corona : null;
        return corona && typeof corona.action === "function"
            ? corona.action("activate application launcher") : null;
    }
    Connections {
        target: root.launcherAction
        ignoreUnknownSignals: true
        function onTriggered() {
            root.noteLauncherToggle();
        }
    }

    // Reads the active task's application name. Called on changes instead of being a binding,
    // so the model's frequent data updates can never form a binding loop.
    function refresh() {
        // While the panel itself has keyboard focus (Tab navigation, a text field in a panel
        // widget), no application window is active; keep the last name, as the global menu does.
        const containment = Plasmoid.containment;
        if (containment && containment.status === PlasmaCore.Types.AcceptingInputStatus) {
            return;
        }
        const index = tasksModel.activeTask;
        if (!index || !index.valid) {
            appName = "";
            return;
        }
        let name = tasksModel.data(index, TaskManager.AbstractTasksModel.AppName);
        if (!name) {
            name = tasksModel.data(index, TaskManager.AbstractTasksModel.GenericName);
        }
        if (!name) {
            name = tasksModel.data(index, Qt.DisplayRole);
        }
        appName = name ? String(name) : "";
    }

    TaskManager.TasksModel {
        id: tasksModel
        // Only the active task matters: no grouping, sorting or filtering work.
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false

        onActiveTaskChanged: {
            root.focusSignals++;
            focusSettle.restart();
            Qt.callLater(root.refresh);
        }
        // Names rarely change, but the model has no per-role signal in QML; refresh() only
        // reads three roles of one row and Qt.callLater folds bursts (window moves) into one.
        onDataChanged: Qt.callLater(root.refresh)
        onCountChanged: Qt.callLater(root.refresh)
    }

    Connections {
        target: Application
        function onStateChanged() {
            focusSettle.restart();
        }
    }

    Connections {
        target: Plasmoid.containment
        function onStatusChanged() {
            Qt.callLater(root.refresh);
        }
    }

    Connections {
        target: Plasmoid
        // The widget's own global shortcut opens the launcher as well.
        function onActivated() {
            root.openLauncher();
        }
    }

    Component.onCompleted: refresh()

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.left: root.vertical ? undefined : parent.left
        LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true
        spacing: 0

        Item {
            width: root.vertical ? 0 : root.startPadding
            height: 1
        }

        // The tooltip area is the outer item: a hover-enabled item on top of a MouseArea would
        // take the hover from it.
        PlasmaCore.ToolTipArea {
            anchors.verticalCenter: parent.verticalCenter
            width: root.buttonWidth
            height: root.buttonHeight
            mainText: i18nc("@info:tooltip", "Open the launcher")
            location: Plasmoid.location
            active: !root.launcherOpen

            MouseArea {
                id: logoButton
                anchors.fill: parent
                hoverEnabled: true
                activeFocusOnTab: true
                acceptedButtons: Qt.LeftButton

                Accessible.role: Accessible.Button
                Accessible.name: i18nc("@action:button", "Open launcher")
                Accessible.onPressAction: root.openLauncher()

                onClicked: root.openLauncher()
                Keys.onPressed: event => {
                    if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select].indexOf(event.key) !== -1) {
                        root.openLauncher();
                        event.accepted = true;
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    antialiasing: true
                    color: logoButton.pressed || root.launcherOpen ? root.tint(0.16)
                         : logoButton.containsMouse ? root.tint(0.10) : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: Kirigami.Units.shortDuration }
                    }
                }

                FusionLogo {
                    anchors.centerIn: parent
                    size: 18
                }

                // Keyboard focus: the Controls board's 2 px ring with a 2 px gap.
                Rectangle {
                    visible: logoButton.activeFocus
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: 12
                    color: "transparent"
                    border.width: 2
                    border.color: root.focusColor
                }
            }
        }

        Item {
            width: root.vertical ? 0 : root.nameGap
            height: 1
        }

        FusionText {
            id: nameLabel
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical
            family: "Manrope"
            px: 13
            weight: 800
            color: Kirigami.Theme.textColor
            text: root.shownName
            elide: Text.ElideRight
            width: Math.min(implicitWidth, root.nameMaxWidth)
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Item {
            width: root.vertical ? 0 : root.nameEndPadding
            height: 1
        }
    }
}
