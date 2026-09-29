/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects

import org.kde.kirigami as Kirigami

// One app in the dock: its icon from the icon theme with a soft drop shadow,
// the running dot (5x4) or active pill (16x4) under it.
Item {
    id: task

    required property int index
    required property var model
    required property DockPalette pal

    property real iconSize: 48
    property int bottomPad: 14

    readonly property bool isLauncher: model.IsLauncher === true
    readonly property bool isStartup: model.IsStartup === true
    readonly property bool isRunning: !isLauncher && !isStartup
    readonly property bool isActive: model.IsActive === true
    readonly property bool demandsAttention: model.IsDemandingAttention === true
    // Launchers of apps that are not installed have no AppId; they are not shown.
    readonly property bool resolvable: !isLauncher || (model.AppId ?? "") !== ""
    readonly property string name: model.AppName || model.display || ""
    readonly property alias hovered: mouse.containsMouse
    readonly property alias pressed: mouse.pressed
    readonly property alias mouseArea: mouse
    readonly property alias iconItem: icon
    readonly property real iconTop: icon.y

    signal activated(int modifiers)
    signal newInstanceRequested()
    signal menuRequested()
    signal dragMoved(real sceneX)
    signal dragFinished()

    visible: resolvable
    width: Math.round(iconSize)
    activeFocusOnTab: visible

    Accessible.role: Accessible.Button
    Accessible.name: name
    Accessible.description: isLauncher ? i18nc("@info:tooltip", "Pinned, not running")
                                       : (isActive ? i18nc("@info:tooltip", "Active") : i18nc("@info:tooltip", "Running"))
    Accessible.onPressAction: task.activated(0)

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Enter:
        case Qt.Key_Return:
        case Qt.Key_Select:
            task.activated(event.modifiers);
            event.accepted = true;
            break;
        case Qt.Key_Menu:
            task.menuRequested();
            event.accepted = true;
            break;
        }
    }

    Kirigami.Icon {
        id: icon
        width: Math.round(task.iconSize)
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        y: task.height - task.bottomPad - height
        source: task.model.decoration
        roundToIconSize: false
        animated: false
        visible: false
    }

    // filter: drop-shadow(0 3px 6px rgba(0,0,0,.35)) in the boards. Blur values were matched
    // to the rendered board: the darkening below a tile is within 1-2 % of it, row by row.
    MultiEffect {
        id: shadowed
        source: icon
        anchors.fill: icon
        shadowEnabled: true
        shadowColor: task.pal.iconShadow
        shadowVerticalOffset: 3
        shadowHorizontalOffset: 0
        shadowBlur: 0.75
        blurMax: 40
        autoPaddingEnabled: true
        opacity: task.isStartup ? startupPulse.value : (mouse.pressed && !mouse.dragging ? 0.75 : 1)
    }

    // Launch feedback: the icon pulses until the app's window appears.
    QtObject {
        id: startupPulse
        property real value: 1
    }

    SequentialAnimation {
        running: task.isStartup
        loops: Animation.Infinite
        onRunningChanged: if (!running) startupPulse.value = 1
        NumberAnimation { target: startupPulse; property: "value"; to: 0.45; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { target: startupPulse; property: "value"; to: 1; duration: 500; easing.type: Easing.InOutSine }
    }

    // Keyboard focus ring around the icon.
    Rectangle {
        anchors.fill: icon
        anchors.margins: -4
        radius: Math.round(icon.width * 0.27) + 4
        color: "transparent"
        border.width: 2
        border.color: task.pal.focusRing
        visible: task.activeFocus
        antialiasing: true
    }

    // Running indicator: 9 px below the icon's bottom edge (bottom:-9px, height 4).
    Rectangle {
        id: indicator
        anchors.horizontalCenter: parent.horizontalCenter
        y: task.height - task.bottomPad + 5
        height: 4
        radius: 2
        width: task.isActive ? 16 : 5
        color: task.isActive ? task.pal.activePill : (task.demandsAttention ? task.pal.attention : task.pal.runningDot)
        visible: task.isRunning || task.isStartup
        opacity: task.isStartup ? startupPulse.value : 1

        Behavior on width {
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: mouse

        property point pressPoint
        property bool dragging: false
        property bool suppressClick: false

        // Reach into the gaps next to the icon so that the pointer is always over one item.
        x: -4
        y: icon.y - 10
        width: parent.width + 8
        height: parent.height - y
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        onPressed: mouse => {
            pressPoint = Qt.point(mouse.x, mouse.y);
            dragging = false;
            suppressClick = false;
        }
        onPositionChanged: mouse => {
            if (!(mouse.buttons & Qt.LeftButton)) {
                return;
            }
            if (!dragging && Math.abs(mouse.x - pressPoint.x) > Qt.styleHints.startDragDistance) {
                dragging = true;
            }
            if (dragging) {
                task.dragMoved(mapToItem(null, mouse.x, mouse.y).x);
            }
        }
        onReleased: mouse => {
            if (dragging) {
                dragging = false;
                suppressClick = true;
                task.dragFinished();
            }
        }
        onCanceled: {
            if (dragging) {
                dragging = false;
                task.dragFinished();
            }
        }
        onClicked: mouse => {
            if (suppressClick) {
                suppressClick = false;
                return;
            }
            if (mouse.button === Qt.RightButton) {
                task.menuRequested();
            } else if (mouse.button === Qt.MiddleButton) {
                task.newInstanceRequested();
            } else {
                task.activated(mouse.modifiers);
            }
        }
    }
}
