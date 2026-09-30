/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

// The panel button: the Fusion logo. In a tall panel (the dock) it is the 48 px Start tile
// with the open indicator under it; in a thin panel (the top bar) it is the 32x26 logo pill,
// scaled with the user's text size like the rest of the top bar.
MouseArea {
    id: button

    property var launcher

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal || vertical
    readonly property real thickness: vertical ? width : height
    readonly property string style: {
        const configured = Plasmoid.configuration.buttonStyle;
        if (configured === "hidden" || configured === "icon") {
            return configured;
        }
        if (!inPanel) {
            return "icon";
        }
        return thickness >= 36 ? "tile" : "pill";
    }
    // The board's Start tile is 48 px; smaller docks get a proportionally smaller tile.
    readonly property real tileSize: Math.max(32, Math.min(48, thickness))
    readonly property bool open: launcher ? launcher.menuOpen : false
    readonly property bool dark: {
        const c = Kirigami.Theme.backgroundColor;
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
    }
    readonly property color ink: dark ? "#ffffff" : "#141827"
    function tint(alpha: real): color {
        return Qt.rgba(ink.r, ink.g, ink.b, alpha);
    }

    property bool wasOpen: false

    // Text scale and pixel grid of the panel window (docs/parts/shell-launcher.md, "Text scale").
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
    }
    readonly property real pillWidth: m.px(32)
    readonly property real pillHeight: m.px(26)

    // Tell the applet that the next `expanded` change comes from the shell showing this button.
    Component.onCompleted: {
        if (launcher && !launcher.expanded) {
            launcher.autoExpandPending = true;
        }
    }

    readonly property real naturalSize: style === "hidden" ? 0 : style === "tile" ? tileSize : style === "pill" ? pillWidth : Kirigami.Units.iconSizes.medium

    // Across the panel the button takes the whole thickness (that decides tile or pill);
    // along the panel it is as long as the tile or pill.
    Layout.fillHeight: !vertical
    Layout.fillWidth: vertical
    Layout.minimumWidth: vertical ? -1 : naturalSize
    Layout.preferredWidth: vertical ? -1 : naturalSize
    Layout.maximumWidth: vertical ? Infinity : naturalSize
    Layout.minimumHeight: vertical ? (style === "pill" ? pillHeight : naturalSize) : -1
    Layout.preferredHeight: vertical ? (style === "pill" ? pillHeight : naturalSize) : -1
    Layout.maximumHeight: vertical ? (style === "pill" ? pillHeight : naturalSize) : Infinity

    implicitWidth: vertical ? 48 : naturalSize
    implicitHeight: vertical ? naturalSize : 48
    visible: style !== "hidden"
    hoverEnabled: true
    activeFocusOnTab: style !== "hidden"

    Accessible.role: Accessible.Button
    Accessible.name: i18nc("@action:button", "Open launcher")
    Accessible.checkable: true
    Accessible.checked: open

    // The card starts building when the pointer reaches the button (BACKLOG S2).
    onContainsMouseChanged: if (containsMouse && launcher) launcher.prepareCard()
    onPressed: wasOpen = launcher ? launcher.recentlyOpen() : false
    onClicked: {
        if (launcher) {
            if (wasOpen) {
                launcher.close();
            } else {
                launcher.open("home");
            }
        }
    }
    Keys.onPressed: event => {
        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select].includes(event.key)) {
            if (launcher) {
                launcher.toggle();
            }
            event.accepted = true;
        }
    }

    // Dock: 48 px Start tile, radius 13. Open: accent tint with a 1 px inner line and the
    // 16x4 indicator under the tile.
    Rectangle {
        id: tile
        visible: button.style === "tile"
        anchors.centerIn: parent
        width: button.tileSize
        height: button.tileSize
        radius: Math.round(button.tileSize * 13 / 48)
        antialiasing: true
        color: button.open ? Qt.rgba(91 / 255, 157 / 255, 1, 0.3)
             : button.containsMouse ? button.tint(0.14) : button.tint(0.08)

        Rectangle {
            anchors.fill: parent
            radius: tile.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(138 / 255, 184 / 255, 1, 0.5)
            visible: button.open
            antialiasing: true
        }

        FusionLogo {
            anchors.centerIn: parent
            size: Math.round(button.tileSize * 28 / 48)
        }
    }

    Rectangle {
        visible: button.style === "tile" && button.open
        anchors.horizontalCenter: tile.horizontalCenter
        anchors.top: tile.bottom
        anchors.topMargin: 5
        width: 16
        height: 4
        radius: 2
        color: button.dark ? "#8ab8ff" : "#2f6fdf"
    }

    // Top bar: 32x26 pill, radius 8, 18 px logo; filled while the launcher is open.
    Rectangle {
        visible: button.style === "pill"
        anchors.centerIn: parent
        width: button.pillWidth
        height: button.pillHeight
        radius: 8
        antialiasing: true
        color: button.open ? button.tint(0.16) : button.containsMouse ? button.tint(0.10) : "transparent"

        FusionLogo {
            anchors.centerIn: parent
            size: m.px(18)
        }
    }

    FusionLogo {
        visible: button.style === "icon"
        anchors.centerIn: parent
        size: Math.min(button.width, button.height)
    }

    Rectangle {
        visible: button.activeFocus && button.style !== "hidden"
        anchors.centerIn: parent
        width: (button.style === "tile" ? button.tileSize : button.pillWidth) + 8
        height: (button.style === "tile" ? button.tileSize : button.pillHeight) + 8
        radius: (button.style === "tile" ? tile.radius : 8) + 4
        color: "transparent"
        border.width: 2
        border.color: button.dark ? "#8ab8ff" : "#2f6fdf"
    }
}
