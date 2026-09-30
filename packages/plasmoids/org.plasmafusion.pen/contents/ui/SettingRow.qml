// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T

// A row of the pen settings page (PEN.md 3.4): 52 px, label (15 px, 700) and hint (12 px, 70 %) on
// the left, the current value (14 px, 600) and a chevron on the right. With choices, a tap opens
// them below the row (44 px each, the current one checked); a pick closes them and reports it.
// Without choices the row is an action (activated()).
Column {
    id: row

    required property FusionMetrics metrics
    required property FusionAccent tint
    required property color ink
    // Names the row's buttons for the tests' log ("row-<key>", "choice-<key>-<id>").
    property string key: ""
    property string label: ""
    property string hint: ""
    property string value: ""
    // [{ "id": ..., "text": ... }]
    property var choices: []
    property string current: ""
    property bool expanded: false

    signal picked(string id)
    signal activated()

    width: parent ? parent.width : 0

    T.AbstractButton {
        id: head
        objectName: row.key.length > 0 ? "row-" + row.key : ""
        width: row.width
        height: row.metrics.px(52)
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        text: row.label
        Accessible.name: row.label
        Accessible.description: row.value.length > 0 ? row.value : row.hint

        onClicked: {
            if (row.choices.length > 0) {
                row.expanded = !row.expanded;
            } else {
                row.activated();
            }
        }
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()

        background: Rectangle {
            radius: row.metrics.px(12)
            color: Qt.rgba(row.ink.r, row.ink.g, row.ink.b, head.down ? 0.12 : head.hovered ? 0.06 : 0)
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 2
                border.color: row.tint.focusRing
                visible: head.visualFocus
            }
        }
        contentItem: Item {
            Column {
                anchors.left: parent.left
                anchors.leftMargin: row.metrics.px(8)
                anchors.right: valueRow.left
                anchors.rightMargin: row.metrics.px(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: row.metrics.px(2)
                Text {
                    width: parent.width
                    text: row.label
                    color: row.ink
                    font.pixelSize: row.metrics.font(15)
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Text {
                    width: parent.width
                    visible: row.hint.length > 0
                    text: row.hint
                    color: row.ink
                    opacity: 0.7
                    font.pixelSize: row.metrics.font(12)
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
            Row {
                id: valueRow
                anchors.right: parent.right
                anchors.rightMargin: row.metrics.px(4)
                anchors.verticalCenter: parent.verticalCenter
                spacing: row.metrics.px(4)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.value
                    color: row.ink
                    opacity: 0.8
                    font.pixelSize: row.metrics.font(14)
                    font.weight: Font.DemiBold
                    textFormat: Text.PlainText
                }
                LineIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    size: row.metrics.px(16)
                    path: "M9 6l6 6-6 6"
                    color: row.ink
                    opacity: 0.6
                    rotation: row.expanded ? 90 : 0
                }
            }
        }
    }

    Repeater {
        model: row.expanded ? row.choices : []

        T.AbstractButton {
            id: choice
            required property var modelData
            objectName: row.key.length > 0 ? "choice-" + row.key + "-" + modelData.id : ""
            width: row.width
            height: row.metrics.px(44)
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            text: modelData.text
            Accessible.name: modelData.text
            Accessible.role: Accessible.RadioButton
            Accessible.checked: modelData.id === row.current

            onClicked: {
                // Report first: closing the choices destroys this delegate.
                const r = row;
                r.picked(modelData.id);
                r.expanded = false;
            }
            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()

            background: Rectangle {
                radius: row.metrics.px(10)
                color: Qt.rgba(row.ink.r, row.ink.g, row.ink.b, choice.down ? 0.12 : choice.hovered ? 0.06 : 0.03)
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 2
                    border.color: row.tint.focusRing
                    visible: choice.visualFocus
                }
            }
            contentItem: Item {
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: row.metrics.px(24)
                    anchors.verticalCenter: parent.verticalCenter
                    text: choice.modelData.text
                    color: row.ink
                    font.pixelSize: row.metrics.font(14)
                    font.weight: choice.modelData.id === row.current ? Font.Bold : Font.Normal
                    textFormat: Text.PlainText
                }
                LineIcon {
                    anchors.right: parent.right
                    anchors.rightMargin: row.metrics.px(8)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: choice.modelData.id === row.current
                    size: row.metrics.px(18)
                    path: "M5 12.5l4.5 4.5L19 7.5"
                    color: row.tint.accent
                }
            }
        }
    }
}
