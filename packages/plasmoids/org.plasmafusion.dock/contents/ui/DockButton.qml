/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// A fixed 48 px dock button (Start, Search, Overview, Downloads, Trash): radius 13,
// 8 % fill, accent fill with a 1 px inner ring while `active` (aria-pressed in the boards). On a
// dock on the left or right (board DockPosition.dc.html) the row is upright: the button is the
// panel's width across, its face on the edge side and its pill beside it.
Item {
    id: button

    required property DockPalette pal
    required property Motion motion
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
    // Set by the dock, which tracks the pointer for the whole row (one hover source: an item's
    // own hover state can stay behind when the pointer jumps off the panel).
    property bool hovered: false
    // The dock's edge ("bottom", "left", "right"), the button's place along the row and its
    // magnification offset (set by the dock).
    property string edge: "bottom"
    readonly property bool vertical: edge !== "bottom"
    property real along: 0
    property real alongShift: 0
    readonly property bool pressed: mouse.pressed

    signal clicked()
    signal menuRequested()

    x: vertical ? 0 : along
    y: vertical ? along : 0
    width: vertical ? (parent ? parent.width : tile) : tile
    height: vertical ? tile : (parent ? parent.height : tile)
    transform: Translate {
        x: button.vertical ? 0 : button.alongShift
        y: button.vertical ? button.alongShift : 0
    }
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

    // The face sits bottomPad from the edge side, centred along the row.
    Rectangle {
        id: face
        x: button.edge === "left" ? button.bottomPad
            : button.edge === "right" ? button.width - button.bottomPad - width : (button.width - width) / 2
        y: button.vertical ? (button.height - height) / 2 : button.height - button.bottomPad - height
        width: button.tile
        height: button.tile
        radius: Math.round(button.tile * 13 / 48)
        antialiasing: true
        color: {
            if (button.active || button.dropHighlight > 0) {
                return button.pal.activeFill;
            }
            if (mouse.pressed) {
                return button.pal.buttonPressed;
            }
            return button.hovered ? button.pal.buttonHover : button.pal.buttonFill;
        }

        Behavior on color {
            enabled: button.motion.animate
            ColorAnimation { duration: button.motion.hover }
        }
        // Press feedback: 0.94 (TABLET 4.4).
        scale: mouse.pressed ? 0.94 : 1
        Behavior on scale {
            enabled: button.motion.animate
            NumberAnimation { duration: button.motion.pressScale; easing.type: button.motion.standardEasing }
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

    // The pill 5 px from the face on the edge side (4 px with the larger tiles), upright on a side.
    Rectangle {
        readonly property int gapToFace: button.tile > 48 ? 4 : 5
        readonly property int length: button.tile > 48 ? 18 : 16
        x: button.edge === "left" ? face.x - gapToFace - width
            : button.edge === "right" ? face.x + face.width + gapToFace : face.x + (face.width - width) / 2
        y: button.vertical ? face.y + (face.height - height) / 2 : face.y + face.height + gapToFace
        width: button.vertical ? 4 : length
        height: button.vertical ? length : 4
        radius: 2
        color: button.pal.activePill
        visible: button.showIndicator
    }

    MouseArea {
        id: mouse
        // Reach into the 8 px gaps so the pointer is always over one item, and 10 px past the
        // face away from the edge.
        x: button.edge === "left" ? 0 : button.edge === "right" ? face.x - 10 : -4
        y: button.vertical ? -4 : face.y - 10
        width: button.edge === "left" ? face.x + face.width + 10 : button.edge === "right" ? parent.width - x : parent.width + 8
        height: button.vertical ? parent.height + 8 : parent.height - y
        hoverEnabled: false
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
