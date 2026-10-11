// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.plasma.core as PlasmaCore

import "Icons.js" as Icons

// Quick settings tile: 60 px tall, 16 px radius, accent fill when on (64 px, radius 18 in tablet
// posture, TABLET 4.6). With "hasDetails" the right part is a separate chevron button that opens
// a list (44 px wide in touch mode).
// Height, paddings, icons and text follow the user's text size (`metrics`); the radius does not.
// In the sheet's edit mode the tile is one control with a remove badge and a drag handle
// (QuickSettingsMain.qml, "Editable tiles" in docs/parts/shell-quicksettings.md).
Item {
    id: tile

    required property FusionPalette pal
    required property FusionMetrics metrics
    property string title: ""
    property string subtitle: ""
    property string iconPath: ""
    property string iconFillPath: ""
    property bool checked: false
    property bool hasDetails: false
    property bool available: true
    property string detailsText: ""
    property string toolTip: ""
    // More about the state than the subtitle says (why, who): read by screen readers with it.
    property string note: ""
    // The tile's id in the order (contents/code/tiles.js) and the page's arrangement of the grid
    // (QuickSettingsMain.qml): `slots`, the shown tiles in order, puts the tile in its cell of the
    // two-column grid; a tile not in it (hidden, or its condition does not hold) is not shown.
    property string tileId: ""
    property var arrangement: null
    readonly property int slot: arrangement ? arrangement.slots.indexOf(tileId) : 0
    visible: slot >= 0
    Layout.row: Math.floor(Math.max(0, slot) / 2)
    Layout.column: Math.max(0, slot) % 2
    // Edit mode: the tile is dragged to its new place, moved with Ctrl and the arrow keys and
    // removed with its badge or Delete (the arrangement does the work); its own actions rest.
    readonly property bool editing: arrangement ? arrangement.editing : false
    readonly property bool lifted: dragger.active
    readonly property alias editButton: editArea
    readonly property alias removeButton: removeBadge
    z: lifted ? 2 : 0
    scale: lifted ? 1.04 : 1
    Behavior on scale {
        enabled: tile.pal.motion.animate
        NumberAnimation { duration: tile.pal.motion.toggle; easing.type: tile.pal.motion.standardEasing }
    }
    // A dragged tile follows the pointer (`lift`); the others glide to their new cells (`glide`,
    // from where they were drawn to where the grid now puts them).
    property point grabPoint: Qt.point(0, 0)
    property point dragPoint: Qt.point(0, 0)
    property real lastX: 0
    property real lastY: 0
    transform: [
        Translate {
            id: lift
            x: tile.lifted ? tile.dragPoint.x - tile.grabPoint.x - tile.x : 0
            y: tile.lifted ? tile.dragPoint.y - tile.grabPoint.y - tile.y : 0
        },
        Translate {
            id: glide
        }
    ]
    ParallelAnimation {
        id: glideBack
        NumberAnimation { target: glide; property: "x"; to: 0; duration: tile.pal.motion.toggle; easing.type: tile.pal.motion.standardEasing }
        NumberAnimation { target: glide; property: "y"; to: 0; duration: tile.pal.motion.toggle; easing.type: tile.pal.motion.standardEasing }
    }
    function glideFrom(dx: real, dy: real): void {
        if (!pal.motion.animate || (dx === 0 && dy === 0)) {
            return;
        }
        glide.x += dx;
        glide.y += dy;
        glideBack.restart();
    }
    onXChanged: {
        if (editing && visible && !lifted) {
            glideFrom(lastX - x, 0);
        }
        lastX = x;
    }
    onYChanged: {
        if (editing && visible && !lifted) {
            glideFrom(0, lastY - y);
        }
        lastY = y;
    }

    signal toggled()
    signal detailsRequested()

    readonly property alias mainButton: mainArea
    readonly property alias detailsButton: chevronArea

    readonly property real radius: pal.tablet ? 18 : 16
    implicitHeight: metrics.px(pal.tablet ? 64 : 60)
    implicitWidth: 158
    // In edit mode every tile is drawn in full: it can be moved or removed whatever its state.
    opacity: available || editing ? 1 : 0.55

    readonly property color foreground: checked ? pal.accentText : pal.text
    readonly property color subForeground: checked ? pal.accentTextSecondary : pal.secondary
    readonly property bool hovered: mainArea.hovered || chevronArea.hovered
    readonly property bool pressed: mainArea.down || chevronArea.down

    Rectangle {
        id: background
        anchors.fill: parent
        radius: tile.radius
        color: {
            if (tile.checked) {
                return tile.pressed ? Qt.darker(tile.pal.accent, 1.12) : (tile.hovered ? Qt.lighter(tile.pal.accent, 1.1) : tile.pal.accent);
            }
            return tile.pal.overlay(tile.pressed ? 0.15 : (tile.hovered || editArea.hovered || tile.lifted ? 0.12 : 0.08));
        }
        // Edit mode: an edge marks every tile as one that can be moved.
        border.width: tile.editing ? 1 : 0
        border.color: tile.pal.overlay(tile.lifted ? 0.4 : 0.22)
        Behavior on color {
            enabled: tile.pal.motion.animate
            ColorAnimation { duration: tile.pal.motion.hover }
        }

        FocusRing {
            baseRadius: tile.radius
            ringColor: tile.pal.focus
            shown: mainArea.visualFocus || editArea.visualFocus
        }
    }

    T.AbstractButton {
        id: mainArea
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            right: tile.hasDetails ? chevronArea.left : parent.right
        }
        enabled: !tile.editing
        focusPolicy: Qt.TabFocus
        hoverEnabled: true
        checkable: false
        text: tile.title
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true
        Accessible.checked: tile.checked
        Accessible.name: tile.title
        Accessible.description: [tile.subtitle, tile.note].filter(t => t !== "").join(". ")
        Keys.onReturnPressed: tile.toggled()
        Keys.onEnterPressed: tile.toggled()
        Keys.onRightPressed: event => {
            if (tile.hasDetails) {
                chevronArea.forceActiveFocus(Qt.TabFocusReason);
            } else {
                event.accepted = false;
            }
        }
        onClicked: tile.toggled()

        contentItem: Item {}
        background: Item {}

        Row {
            anchors {
                left: parent.left
                leftMargin: tile.metrics.px(14)
                right: parent.right
                rightMargin: tile.hasDetails ? 0 : tile.metrics.px(14)
                verticalCenter: parent.verticalCenter
            }
            spacing: tile.metrics.px(10)

            LineIcon {
                id: tileIcon
                anchors.verticalCenter: parent.verticalCenter
                size: tile.metrics.px(20)
                path: tile.iconPath
                fillPath: tile.iconFillPath
                color: tile.foreground
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - tileIcon.width - parent.spacing
                spacing: 1

                FText {
                    pal: tile.pal
                    metrics: tile.metrics
                    width: parent.width
                    text: tile.title
                    color: tile.foreground
                    font.weight: Font.ExtraBold
                    px: 13
                }
                FText {
                    pal: tile.pal
                    metrics: tile.metrics
                    width: parent.width
                    text: tile.subtitle
                    visible: text.length > 0
                    color: tile.subForeground
                    px: 11.5
                }
            }
        }

        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            mainText: tile.title
            subText: tile.toolTip
            active: tile.toolTip.length > 0
            location: PlasmaCore.Types.Floating
        }
    }

    T.AbstractButton {
        id: chevronArea
        visible: tile.hasDetails && !tile.editing
        width: tile.hasDetails ? Math.max(tile.metrics.px(34), tile.pal.touch ? 44 : 0) : 0
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        focusPolicy: Qt.TabFocus
        hoverEnabled: true
        text: tile.detailsText
        Accessible.role: Accessible.Button
        Accessible.name: tile.detailsText
        Keys.onReturnPressed: tile.detailsRequested()
        Keys.onEnterPressed: tile.detailsRequested()
        Keys.onLeftPressed: mainArea.forceActiveFocus(Qt.TabFocusReason)
        onClicked: tile.detailsRequested()

        contentItem: Item {}
        background: Item {
            FocusRing {
                anchors.margins: 2
                baseRadius: 12
                // Drawn inside the tile: white on the accent fill, where the accent ring would vanish.
                ringColor: tile.checked ? tile.pal.accentText : tile.pal.focus
                shown: chevronArea.visualFocus
            }
        }

        LineIcon {
            anchors {
                right: parent.right
                rightMargin: tile.metrics.px(10)
                verticalCenter: parent.verticalCenter
            }
            size: tile.metrics.px(14)
            path: "M9 6l6 6-6 6"
            color: tile.foreground
        }

        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            mainText: tile.detailsText
            active: tile.detailsText.length > 0
            location: PlasmaCore.Types.Floating
        }
    }

    // ---- Edit mode: the whole tile drags; Ctrl+arrow keys move it, Delete removes it.
    T.Control {
        id: editArea
        objectName: "edit-" + tile.tileId
        anchors.fill: parent
        visible: tile.editing
        focusPolicy: Qt.TabFocus
        hoverEnabled: true
        Accessible.role: Accessible.Button
        Accessible.name: tile.title
        Accessible.description: tile.arrangement ? tile.arrangement.describe(tile.tileId) : ""
        Keys.onPressed: event => {
            if (tile.arrangement) {
                tile.arrangement.keyPressed(tile.tileId, event);
            }
        }
        contentItem: Item {}
        background: Item {}

        DragHandler {
            id: dragger
            target: null
            enabled: tile.editing
            // Once it moves the tile, the sheet's scrolling does not take the drag over.
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            onActiveChanged: {
                if (active) {
                    tile.grabPoint = centroid.pressPosition;
                    tile.dragPoint = tile.parent.mapFromItem(null, centroid.scenePosition);
                    tile.arrangement.dragStarted(tile.tileId);
                } else {
                    // Let go: the tile glides from under the pointer into its cell.
                    tile.glideFrom(tile.dragPoint.x - tile.grabPoint.x - tile.x, tile.dragPoint.y - tile.grabPoint.y - tile.y);
                    tile.arrangement.dragFinished(tile.tileId);
                }
            }
            onCentroidChanged: {
                if (active) {
                    tile.dragPoint = tile.parent.mapFromItem(null, centroid.scenePosition);
                    tile.arrangement.dragMoved(tile.tileId, tile.dragPoint.x - tile.grabPoint.x + tile.width / 2,
                                               tile.dragPoint.y - tile.grabPoint.y + tile.height / 2);
                }
            }
        }
    }

    // The drag handle, where the chevron is.
    LineIcon {
        visible: tile.editing
        anchors {
            right: parent.right
            rightMargin: tile.metrics.px(10)
            verticalCenter: parent.verticalCenter
        }
        size: tile.metrics.px(16)
        path: Icons.grip
        strokeWidth: 2.6
        color: tile.foreground
        opacity: 0.7
    }

    // The remove badge at the top right; its target is larger than the drawn circle (44
    // in touch mode).
    T.AbstractButton {
        id: removeBadge
        objectName: "remove-" + tile.tileId
        readonly property real badgeSize: tile.pal.tablet ? 24 : 22
        visible: tile.editing && !tile.lifted
        width: Math.max(28, tile.pal.touch ? 44 : 0)
        height: width
        // Flush with the tile's right edge (the sheet clips what passes its side) and over its top.
        x: tile.width - badgeSize / 2 - width / 2
        y: 4 - height / 2
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        text: i18nc("@action:button %1 tile name", "Remove %1", tile.title)
        Accessible.role: Accessible.Button
        Accessible.name: text
        onClicked: tile.arrangement.hide(tile.tileId)
        contentItem: Item {}
        background: Rectangle {
            x: (removeBadge.width - width) / 2
            y: (removeBadge.height - height) / 2
            width: removeBadge.badgeSize
            height: width
            radius: width / 2
            color: removeBadge.down ? Qt.darker(tile.pal.playFill, 1.15) : (removeBadge.hovered ? Qt.darker(tile.pal.playFill, 1.07) : tile.pal.playFill)
            LineIcon {
                anchors.centerIn: parent
                size: 16
                strokeWidth: 2.2
                path: Icons.minus
                color: tile.pal.playGlyph
            }
        }
        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            mainText: removeBadge.text
            active: !tile.pal.touch
            location: PlasmaCore.Types.Floating
        }
    }
}
