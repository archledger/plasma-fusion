/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// App tile of the launcher grids: 84 px tall, radius 14, 52 px icon with a soft drop shadow, 12 px name.
// The height, the name and its gap follow the user's text size; the icon keeps its size.
Item {
    id: tile

    required property int index
    required property var model

    readonly property NavGrid grid: GridView.view as NavGrid
    readonly property bool isCurrent: GridView.isCurrentItem
    readonly property bool keyboardCurrent: isCurrent && grid !== null && grid.activeFocus
    readonly property string label: grid ? grid.labelFor(model) : (model.display || "")
    readonly property real nameGap: grid && grid.metrics ? grid.metrics.px(7) : 7

    width: grid ? grid.cellWidth - grid.gap : 102
    height: grid ? grid.cellHeight - grid.gap : 84

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: model.description || ""

    // Pointer hover counts only once the pointer moved (see NavGrid.pointerMovedTo).
    readonly property bool hovered: mouse.containsMouse && grid !== null && grid.pointerActive

    // The full app name when the tile shows a short design name or an elided one.
    PC3.ToolTip.text: model.display || ""
    PC3.ToolTip.visible: hovered && (label !== (model.display || "") || name.truncated)
    PC3.ToolTip.delay: 700

    Rectangle {
        anchors.fill: parent
        radius: 14
        antialiasing: true
        color: (tile.hovered || tile.keyboardCurrent) && tile.grid ? tile.grid.pal.tileHover : "transparent"

        FocusRing {
            anchors.margins: 0
            visible: tile.keyboardCurrent && tile.grid.keyboardNavigation
            baseRadius: 14
            radius: 14
            ringColor: tile.grid ? tile.grid.pal.focusRing : "transparent"
        }
    }

    Kirigami.Icon {
        id: icon
        // Tiles sit at fractional x (board columns are 101.67 px); keep the icon on whole pixels.
        x: Math.round(tile.x + (tile.width - width) / 2) - tile.x
        y: Math.round((tile.height - (52 + tile.nameGap + name.height)) / 2)
        width: 52
        height: 52
        source: tile.model.decoration || "application-x-executable"
        roundToIconSize: false
        animated: false

        // Drop shadow 0 3 6 rgba(0,0,0,0.3); skipped on the software renderer (no shader effects).
        layer.enabled: tile.GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: tile.grid ? tile.grid.pal.iconShadow : "transparent"
            shadowVerticalOffset: 3
            shadowHorizontalOffset: 0
            blurMax: 12
            shadowBlur: 0.5
            autoPaddingEnabled: true
        }
    }

    FusionText {
        id: name
        anchors.top: icon.bottom
        anchors.topMargin: tile.nameGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 8
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        text: tile.label
        color: tile.grid ? tile.grid.pal.tileText : "white"
        metrics: tile.grid ? tile.grid.metrics : null
        px: 12
        weight: 600
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPositionChanged: mouseEvent => {
            if (tile.grid && tile.grid.pointerMovedTo(mouse, mouseEvent.x, mouseEvent.y)) {
                tile.grid.keyboardNavigation = false;
                tile.grid.currentIndex = tile.index;
            }
        }
        onClicked: mouseEvent => {
            if (!tile.grid) {
                return;
            }
            if (mouseEvent.button === Qt.RightButton) {
                tile.grid.currentIndex = tile.index;
                tile.grid.openMenu(tile.index, tile, mouseEvent.x, mouseEvent.y);
            } else {
                tile.grid.launch(tile.index);
            }
        }
    }
}
