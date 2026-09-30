// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// 44 px list row of the drill-down pages: icon, name, status text, trailing mark.
// Height, paddings, icons and text follow the user's text size (`metrics`).
T.AbstractButton {
    id: row

    required property FusionPalette pal
    required property FusionMetrics metrics
    property string iconPath: ""
    property string iconName: ""
    property string status: ""
    property bool selected: false
    property bool busy: false
    property string trailingPath: ""

    implicitHeight: metrics.px(44)
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    Accessible.name: text
    Accessible.description: status
    Accessible.role: Accessible.Button
    Keys.onReturnPressed: row.clicked()
    Keys.onEnterPressed: row.clicked()

    background: Rectangle {
        radius: 10
        color: row.down ? row.pal.overlay(0.1) : (row.hovered || row.selected ? row.pal.overlay(0.06) : "transparent")
        FocusRing {
            anchors.margins: -2
            baseRadius: 10
            ringColor: row.pal.focus
            shown: row.visualFocus
        }
    }

    contentItem: RowLayout {
        spacing: row.metrics.px(12)

        Item {
            Layout.leftMargin: row.metrics.px(10)
            Layout.preferredWidth: row.metrics.px(20)
            Layout.preferredHeight: row.metrics.px(20)
            LineIcon {
                anchors.fill: parent
                visible: row.iconPath.length > 0
                size: row.metrics.px(20)
                path: row.iconPath
                color: row.pal.text
            }
            Kirigami.Icon {
                anchors.fill: parent
                visible: row.iconPath.length === 0 && row.iconName.length > 0
                source: row.iconName
                color: row.pal.text
                isMask: true
            }
        }
        FText {
            Layout.fillWidth: true
            pal: row.pal
            metrics: row.metrics
            text: row.text
            font.weight: Font.Bold
        }
        FText {
            visible: row.status.length > 0
            pal: row.pal
            metrics: row.metrics
            text: row.status
            color: row.pal.secondary
            px: 11.5
            opacity: row.busy ? 0.7 : 1
        }
        LineIcon {
            Layout.rightMargin: row.metrics.px(10)
            visible: row.trailingPath.length > 0
            size: row.metrics.px(16)
            path: row.trailingPath
            color: row.pal.accentSoft
        }
        Item {
            Layout.preferredWidth: 0
            Layout.rightMargin: row.trailingPath.length > 0 ? 0 : row.metrics.px(10)
        }
    }
}
