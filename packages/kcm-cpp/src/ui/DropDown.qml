/*
    Drop-down (board Gestures.dc.html, the Controls board's drop-down): 34 px high, radius 10, the
    surface2 fill with a 1 px border, 12 px ExtraBold text and a 14 px chevron; while its list is
    open, the 1.5 px focus border with the accent's 3 px soft ring. The list is the Controls
    board's menu: radius 14, 6 px padding, 32 px items with radius 8, the chosen one in the accent's
    soft fill with a check, a line after the first item (Nothing). It opens under the drop-down,
    at its right edge.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

T.ComboBox {
    id: control

    required property FusionPalette pal
    property string accessibleName

    implicitWidth: pal.m.px(180)
    implicitHeight: pal.m.px(34)
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.name: accessibleName
    Accessible.description: displayText

    readonly property bool ringed: popup.visible || visualFocus

    background: Item {
        // The accent's soft ring outside the border (box-shadow 0 0 0 3px).
        Rectangle {
            visible: control.ringed
            anchors.fill: parent
            anchors.margins: -3
            radius: 13
            color: control.pal.optionSelected
        }
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: control.pal.dropBackground
            border.width: control.ringed ? 1.5 : 1
            border.color: control.ringed ? control.pal.focusRing : control.pal.dropBorder
        }
    }

    contentItem: Text {
        leftPadding: control.pal.m.px(12)
        rightPadding: control.pal.m.px(10) + 14 + 6
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: control.displayText
        font.family: control.pal.family
        font.pixelSize: control.pal.m.font(12)
        font.weight: Font.ExtraBold
        color: control.pal.text
    }

    // The board's chevron (24-unit path M6 9l6 6 6-6, stroke 1.8), up while the list is open.
    indicator: Shape {
        x: control.width - width - control.pal.m.px(10)
        y: (control.height - height) / 2
        width: 14
        height: 14
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            scale: Qt.size(14 / 24, 14 / 24)
            strokeColor: control.pal.text
            strokeWidth: 1.8 * 14 / 24 // the SVG's stroke scales with its view box; a Shape's does not
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: control.popup.visible ? "M6 15l6-6 6 6" : "M6 9l6 6 6-6"
            }
        }
    }

    delegate: T.ItemDelegate {
        id: option
        required property int index
        required property string modelData
        readonly property bool chosen: index === control.currentIndex

        width: ListView.view ? ListView.view.width : implicitWidth
        height: control.pal.m.px(32) + (index === 0 ? 9 : 1)
        hoverEnabled: true
        highlighted: control.highlightedIndex === index
        text: modelData

        Accessible.role: Accessible.ListItem
        Accessible.name: modelData
        Accessible.selected: chosen

        background: Item {
            Rectangle {
                width: parent.width
                height: control.pal.m.px(32)
                radius: 8
                color: option.chosen ? control.pal.optionSelected
                    : (option.highlighted || option.hovered) ? control.pal.segmentHover : "transparent"
            }
            // The line after Nothing (4 px above and below, as the board's separator).
            Rectangle {
                visible: option.index === 0
                x: 6
                y: control.pal.m.px(32) + 4
                width: parent.width - 12
                height: 1
                color: control.pal.dropBorder
            }
        }
        contentItem: Item {
            implicitHeight: control.pal.m.px(32)
            Text {
                x: 10
                width: parent.width - 20 - (option.chosen ? 16 + 10 : 0)
                height: control.pal.m.px(32)
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: option.text
                font.family: control.pal.family
                font.pixelSize: control.pal.m.font(13)
                font.weight: option.chosen ? Font.Bold : Font.Normal
                color: option.chosen ? control.pal.labelSelected : control.pal.text
            }
            // The board's check (M5 12.5l4.5 4.5L19 7.5, stroke 1.8).
            Shape {
                visible: option.chosen
                x: parent.width - width - 10
                y: (control.pal.m.px(32) - height) / 2
                width: 16
                height: 16
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    scale: Qt.size(16 / 24, 16 / 24)
                    strokeColor: control.pal.labelSelected
                    strokeWidth: 1.8 * 16 / 24
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg {
                        path: "M5 12.5l4.5 4.5L19 7.5"
                    }
                }
            }
        }
    }

    popup: T.Popup {
        x: control.width - width
        y: control.height + 6
        width: Math.max(control.pal.m.px(220), control.width)
        padding: 6
        implicitHeight: contentItem.implicitHeight + 12

        contentItem: ListView {
            implicitHeight: contentHeight
            clip: true
            interactive: contentHeight > height
            spacing: 1
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
        }

        background: Kirigami.ShadowedRectangle {
            radius: 14
            color: control.pal.menuBackground
            border.width: 1
            border.color: control.pal.dropBorder
            shadow.size: 40
            shadow.yOffset: 16
            shadow.color: control.pal.menuShadow
        }
    }
}
