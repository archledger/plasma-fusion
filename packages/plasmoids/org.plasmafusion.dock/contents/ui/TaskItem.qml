/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

import org.kde.kirigami as Kirigami

// One app in the dock: its icon from the icon theme with a soft drop shadow,
// the running dot (5x4) or active pill (16x4) under it.
//
// The item keeps its rest size (`iconSize`) and rest position. Magnification never changes a
// size: the dock sets `grow` (extra px of the magnified icon) and `shift` (horizontal offset),
// the icon box scales around its bottom centre and the whole item is translated. So nothing is
// laid out, re-rasterised or re-blurred while the pointer moves (EFFECTS.md section 4).
Item {
    id: task

    required property int index
    required property var model
    required property DockPalette pal

    property real iconSize: 48
    property int bottomPad: 14
    // Magnification of this frame, set by the dock.
    property real grow: 0
    property real shift: 0
    // Size of the crisp magnified icon; it is loaded once the dock was first hovered.
    property int zoomSize: 62
    property bool zoomReady: false

    readonly property bool isLauncher: model.IsLauncher === true
    readonly property bool isStartup: model.IsStartup === true
    readonly property bool isRunning: !isLauncher && !isStartup
    readonly property bool isActive: model.IsActive === true
    readonly property bool demandsAttention: model.IsDemandingAttention === true
    // Launchers of apps that are not installed have no AppId; they are not shown.
    readonly property bool resolvable: !isLauncher || (model.AppId ?? "") !== ""
    readonly property string name: model.AppName || model.display || ""
    // Set by the dock, which knows from its magnification which icon is under the pointer; the
    // item's own MouseArea does not track hover (one hover pass per pointer event for the whole
    // dock instead of one per item).
    property bool hovered: false
    readonly property alias pressed: mouse.pressed
    readonly property alias mouseArea: mouse
    readonly property alias iconItem: iconBox
    readonly property real iconTop: iconBox.y
    readonly property real magnification: (iconSize + grow) / iconSize

    signal activated(int modifiers)
    signal newInstanceRequested()
    signal menuRequested()
    signal dragMoved(real sceneX)
    signal dragFinished()

    visible: resolvable
    width: Math.round(iconSize)
    activeFocusOnTab: visible
    transform: Translate { x: task.shift }

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

    // The icon at rest size; scaled (never resized) while magnified.
    Item {
        id: iconBox
        width: Math.round(task.iconSize)
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        y: task.height - task.bottomPad - height
        opacity: task.isStartup ? startupPulse.value : (mouse.pressed && !mouse.dragging ? 0.75 : 1)
        transform: Scale {
            origin.x: iconBox.width / 2
            origin.y: iconBox.height
            xScale: task.magnification
            yScale: task.magnification
        }

        // Source of the shadow (hidden: MultiEffect draws it).
        Kirigami.Icon {
            id: shadowSource
            anchors.fill: parent
            source: task.model.decoration
            roundToIconSize: false
            animated: false
            visible: false
        }

        // filter: drop-shadow(0 3px 6px rgba(0,0,0,.35)) in the boards. Blur values were matched
        // to the rendered board: the darkening below a tile is within 1-2 % of it, row by row.
        // Its size never changes, so it is rendered once and only transformed afterwards.
        MultiEffect {
            source: shadowSource
            anchors.fill: shadowSource
            shadowEnabled: true
            shadowColor: task.pal.iconShadow
            shadowVerticalOffset: 3
            shadowHorizontalOffset: 0
            shadowBlur: 0.75
            blurMax: 40
            autoPaddingEnabled: true
        }

        // The crisp icon on top: at rest size, or at the magnified size while magnified (so a
        // scaled-up texture is never shown).
        Kirigami.Icon {
            id: restIcon
            anchors.fill: parent
            source: task.model.decoration
            roundToIconSize: false
            animated: false
            visible: !zoomLoader.item || task.grow <= 0.5
        }

        Loader {
            id: zoomLoader
            active: task.zoomReady && task.zoomSize > task.iconSize
            asynchronous: true
            anchors.centerIn: parent
            sourceComponent: Kirigami.Icon {
                width: task.zoomSize
                height: task.zoomSize
                scale: task.iconSize / task.zoomSize
                source: task.model.decoration
                roundToIconSize: false
                animated: false
                visible: task.grow > 0.5
            }
        }
    }

    // Launch feedback: the icon pulses until the app's window appears, at most three times.
    QtObject {
        id: startupPulse
        property real value: 1
    }

    SequentialAnimation {
        id: pulseAnimation
        loops: 3
        onStopped: startupPulse.value = 1
        NumberAnimation { target: startupPulse; property: "value"; to: 0.45; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { target: startupPulse; property: "value"; to: 1; duration: 500; easing.type: Easing.InOutSine }
    }

    // Restarted on every launch (a binding on `running` would be dropped when the animation
    // stops itself); no pulse with animations turned off.
    function updatePulse(): void {
        if (isStartup && Kirigami.Units.longDuration > 0) {
            pulseAnimation.restart();
        } else {
            pulseAnimation.stop();
            startupPulse.value = 1;
        }
    }
    onIsStartupChanged: updatePulse()
    Component.onCompleted: updatePulse()

    // Keyboard focus ring around the icon.
    Rectangle {
        anchors.fill: iconBox
        anchors.margins: -4
        radius: Math.round(iconBox.width * 0.27) + 4
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

        // Reach into the gaps next to the icon so that the pointer is always over one item: the
        // rest size plus the 4 px gap on each side, widened by the icon's growth so that the
        // magnified neighbours never leave a gap without an item between them.
        x: -4 - task.grow / 2
        y: iconBox.y - 10 - task.grow
        width: parent.width + 8 + task.grow
        height: parent.height - y
        hoverEnabled: false
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
