/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// A fixed 48 px dock button (Start, Search, Overview, Downloads, Trash): radius 13,
// 8 % fill, accent fill with a 1 px inner ring while `active` (aria-pressed in the boards).
Item {
    id: button

    required property DockPalette pal
    property string text
    property string description
    property bool active: false
    // 16x4 accent pill under the button (Start while the launcher is open, Launcher board).
    property bool showIndicator: false
    property bool acceptsMenu: false
    property int bottomPad: 14
    property int tile: 48
    property real dropHighlight: 0
    // Start and Search remember, when pressed, whether the launcher was open at that moment.
    property bool launcherWasOpen: false
    // Whether the last clicked() came from the pointer (true) or the keyboard (false).
    property bool clickFromPointer: false

    default property alias content: face.data
    readonly property alias face: face
    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed

    signal clicked()
    signal menuRequested()

    width: tile
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.description: description
    Accessible.onPressAction: button.clicked()

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Enter:
        case Qt.Key_Return:
        case Qt.Key_Select:
            button.clickFromPointer = false;
            button.clicked();
            event.accepted = true;
            break;
        case Qt.Key_Menu:
            if (button.acceptsMenu) {
                button.menuRequested();
                event.accepted = true;
            }
            break;
        }
    }

    Rectangle {
        id: face
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: button.bottomPad
        width: button.tile
        height: button.tile
        radius: 13
        antialiasing: true
        color: {
            if (button.active || button.dropHighlight > 0) {
                return button.pal.activeFill;
            }
            if (mouse.pressed) {
                return button.pal.buttonPressed;
            }
            return mouse.containsMouse ? button.pal.buttonHover : button.pal.buttonFill;
        }

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
    }

    // box-shadow: inset 0 0 0 1px in the boards: the ring lies over the accent fill.
    Rectangle {
        anchors.fill: face
        radius: face.radius
        color: "transparent"
        border.width: 1
        border.color: button.pal.activeRing
        antialiasing: true
        visible: button.active || button.dropHighlight > 0
    }

    // Keyboard focus: 2 px accent ring with a 2 px gap (Controls board).
    Rectangle {
        anchors.fill: face
        anchors.margins: -4
        radius: face.radius + 4
        color: "transparent"
        border.width: 2
        border.color: button.pal.focusRing
        visible: button.activeFocus
        antialiasing: true
    }

    Rectangle {
        anchors.horizontalCenter: face.horizontalCenter
        y: face.y + face.height + 5
        width: 16
        height: 4
        radius: 2
        color: button.pal.activePill
        visible: button.showIndicator
    }

    MouseArea {
        id: mouse
        // Reach into the 8 px gaps so the pointer is always over one item.
        x: -4
        y: face.y - 10
        width: parent.width + 8
        height: parent.height - y
        hoverEnabled: true
        acceptedButtons: button.acceptsMenu ? (Qt.LeftButton | Qt.RightButton) : Qt.LeftButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                button.menuRequested();
            } else {
                button.clickFromPointer = true;
                button.clicked();
            }
        }
    }
}
