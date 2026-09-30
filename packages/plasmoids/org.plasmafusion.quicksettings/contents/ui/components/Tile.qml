// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T
import org.kde.plasma.core as PlasmaCore

// Quick settings tile: 60 px tall, 16 px radius, accent fill when on (64 px, radius 18 in tablet
// posture, TABLET 4.6). With "hasDetails" the right part is a separate chevron button that opens
// a list (44 px wide in touch mode).
// Height, paddings, icons and text follow the user's text size (`metrics`); the radius does not.
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

    signal toggled()
    signal detailsRequested()

    readonly property alias mainButton: mainArea
    readonly property alias detailsButton: chevronArea

    readonly property real radius: pal.tablet ? 18 : 16
    implicitHeight: metrics.px(pal.tablet ? 64 : 60)
    implicitWidth: 158
    opacity: available ? 1 : 0.55

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
            return tile.pal.overlay(tile.pressed ? 0.15 : (tile.hovered ? 0.12 : 0.08));
        }
        Behavior on color {
            enabled: tile.pal.motion.animate
            ColorAnimation { duration: tile.pal.motion.hover }
        }

        FocusRing {
            baseRadius: tile.radius
            ringColor: tile.pal.focus
            shown: mainArea.visualFocus
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
        focusPolicy: Qt.TabFocus
        hoverEnabled: true
        checkable: false
        text: tile.title
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true
        Accessible.checked: tile.checked
        Accessible.name: tile.title
        Accessible.description: tile.subtitle
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
        visible: tile.hasDetails
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
}
