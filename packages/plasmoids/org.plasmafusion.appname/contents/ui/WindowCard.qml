/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// The window card of the tablet window pill (TABLET 4.3): what the title bar offers, for the
// active window. 320 px wide; a 56 px header (app icon 32, app name 15 px 800, window title
// 12.5 px at 75 %); 52 px rows (glyph 20, label 15 px 600): "Full screen" with a switch (off:
// this window only is windowed, with its title bar, LEAD-1 resolution 11), "Split left",
// "Split right", "Minimize", "Close" (#D9434B). The card's owner runs the actions.
FocusScope {
    id: card

    required property FusionMetrics metrics
    required property Motion motion
    property string appName: ""
    property string title: ""
    property var icon: ""
    property string iconName: ""
    property bool maximized: false

    signal actionRequested(string action)
    signal closeRequested()

    readonly property color ink: Kirigami.Theme.textColor
    readonly property color danger: "#D9434B"
    readonly property real pad: metrics.px(8)

    implicitWidth: metrics.px(320)
    implicitHeight: column.implicitHeight + 2 * pad
    width: implicitWidth
    height: implicitHeight

    Accessible.role: Accessible.Pane
    Accessible.name: i18nc("@title accessible name of the window card", "Window actions: %1", appName)

    Keys.onEscapePressed: closeRequested()
    Keys.onUpPressed: event => {
        const item = nextItemInFocusChain(false);
        if (item) {
            item.forceActiveFocus(Qt.BacktabFocusReason);
        }
    }
    Keys.onDownPressed: event => {
        const item = nextItemInFocusChain(true);
        if (item) {
            item.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    Column {
        id: column
        x: card.pad
        y: card.pad
        width: card.width - 2 * card.pad

        // Header: app icon, app name, window title.
        Item {
            width: parent.width
            height: card.metrics.px(56)

            FusionIconTile {
                id: headerIcon
                x: card.metrics.px(8)
                anchors.verticalCenter: parent.verticalCenter
                size: card.metrics.px(32)
                source: card.icon
                iconName: card.iconName
            }
            Column {
                anchors.left: headerIcon.right
                anchors.leftMargin: card.metrics.px(12)
                anchors.right: parent.right
                anchors.rightMargin: card.metrics.px(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: card.metrics.px(2)

                FusionText {
                    width: parent.width
                    metrics: card.metrics
                    px: 15
                    weight: 800
                    color: card.ink
                    text: card.appName
                    elide: Text.ElideRight
                }
                FusionText {
                    width: parent.width
                    visible: text !== "" && text !== card.appName
                    metrics: card.metrics
                    px: 12.5
                    weight: 400
                    color: card.ink
                    opacity: 0.75
                    text: card.title
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            width: parent.width
            height: card.metrics.hairline
            color: card.ink
            opacity: 0.12
        }
        Item {
            width: 1
            height: card.metrics.px(4)
        }

        CardRow {
            id: fullRow
            key: "fullscreen"
            focus: true
            text: i18nc("@action:button window card switch", "Full screen")
            glyph: "M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"
            isSwitch: true
            checked: card.maximized
            onClicked: card.actionRequested(card.maximized ? "windowed" : "fullscreen")
        }
        CardRow {
            key: "left"
            text: i18nc("@action:button window card", "Split left")
            glyph: "M4 5h16v14H4zM12 5v14M6.5 9h3M6.5 12h3M6.5 15h3"
            onClicked: card.actionRequested("left")
        }
        CardRow {
            key: "right"
            text: i18nc("@action:button window card", "Split right")
            glyph: "M4 5h16v14H4zM12 5v14M14.5 9h3M14.5 12h3M14.5 15h3"
            onClicked: card.actionRequested("right")
        }
        CardRow {
            key: "minimize"
            text: i18nc("@action:button window card", "Minimize")
            glyph: "M6 17h12"
            onClicked: card.actionRequested("minimize")
        }
        CardRow {
            key: "close"
            text: i18nc("@action:button window card", "Close")
            glyph: "M6.5 6.5l11 11M17.5 6.5l-11 11"
            color: card.danger
            onClicked: card.actionRequested("close")
        }
    }

    // Where the rows are, for the tests' log: "key x,y; ..." (row centres, offset by ox, oy).
    function rowCentres(ox: real, oy: real): string {
        const out = [];
        for (let i = 0; i < column.children.length; ++i) {
            const item = column.children[i];
            if (item.objectName.startsWith("windowCard-")) {
                const c = item.mapToItem(null, item.width / 2, item.height / 2);
                out.push(item.objectName.slice(11) + " " + Math.round(ox + c.x) + "," + Math.round(oy + c.y));
            }
        }
        return out.join("; ");
    }

    component CardRow: T.AbstractButton {
        id: rowButton

        property string key: ""
        property string glyph: ""
        property bool isSwitch: false
        property color color: card.ink

        objectName: "windowCard-" + key
        width: column.width
        height: card.metrics.px(52)
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        checkable: false
        Accessible.role: isSwitch ? Accessible.CheckBox : Accessible.Button
        Accessible.name: text
        Accessible.checkable: isSwitch
        Accessible.checked: isSwitch && checked
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Keys.onSpacePressed: clicked()

        background: Rectangle {
            radius: card.metrics.px(14)
            color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, rowButton.down ? 0.14 : rowButton.hovered ? 0.07 : 0)
            Behavior on color {
                enabled: card.motion.animate
                ColorAnimation { duration: card.motion.hover }
            }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 2
                border.color: Kirigami.Theme.focusColor
                visible: rowButton.visualFocus
            }
        }

        contentItem: Item {
            LineIcon {
                id: glyphItem
                x: card.metrics.px(12)
                anchors.verticalCenter: parent.verticalCenter
                size: card.metrics.px(20)
                path: rowButton.glyph
                color: rowButton.color
            }
            FusionText {
                anchors.left: glyphItem.right
                anchors.leftMargin: card.metrics.px(14)
                anchors.right: switchTrack.visible ? switchTrack.left : parent.right
                anchors.rightMargin: card.metrics.px(12)
                anchors.verticalCenter: parent.verticalCenter
                metrics: card.metrics
                px: 15
                weight: 600
                color: rowButton.color
                text: rowButton.text
                elide: Text.ElideRight
            }
            // 40 x 22 switch, 18 px knob (the quick-settings switch).
            Rectangle {
                id: switchTrack
                visible: rowButton.isSwitch
                anchors.right: parent.right
                anchors.rightMargin: card.metrics.px(12)
                anchors.verticalCenter: parent.verticalCenter
                width: card.metrics.px(40)
                height: card.metrics.px(22)
                radius: height / 2
                color: rowButton.checked ? Kirigami.Theme.highlightColor
                                         : Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.2)
                Rectangle {
                    x: rowButton.checked ? parent.width - width - card.metrics.px(2) : card.metrics.px(2)
                    anchors.verticalCenter: parent.verticalCenter
                    width: card.metrics.px(18)
                    height: width
                    radius: width / 2
                    color: "#ffffff"
                    Behavior on x {
                        enabled: card.motion.animate
                        NumberAnimation { duration: card.motion.toggle; easing.type: card.motion.standardEasing }
                    }
                }
            }
        }
    }
}
