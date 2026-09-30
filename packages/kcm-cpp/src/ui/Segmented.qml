/*
    Segmented control (Main board "Window buttons"): 34 px track, 3 px padding and gaps,
    radius 10; the chosen segment is an accent pill with white ExtraBold text.
    Segment widths follow the board's flex layout: text width plus an equal share of the rest.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

Rectangle {
    id: control

    required property FusionPalette pal
    property var model: []
    property int currentIndex: 0
    property string accessibleName
    signal activated(int index)

    implicitHeight: 34
    implicitWidth: 3 * 2 + textSum + (model.length - 1) * 3 + model.length * 24
    radius: 10
    color: pal.segmentBackground

    Accessible.role: Accessible.Grouping
    Accessible.name: accessibleName

    // Widths measured at the chosen (ExtraBold) weight, so segments do not move when chosen.
    readonly property var textWidths: {
        const widths = [];
        for (let i = 0; i < model.length; ++i) {
            widths.push(Math.ceil(metrics.advanceWidth(model[i])));
        }
        return widths;
    }
    readonly property real textSum: textWidths.reduce((a, b) => a + b, 0)
    // Narrowest width that still fits every label (no share of the rest).
    readonly property real minimumWidth: 3 * 2 + textSum + (model.length - 1) * 3
    readonly property real share: Math.max(0, (width - 6 - (model.length - 1) * 3 - textSum) / Math.max(1, model.length))

    FontMetrics {
        id: metrics
        font.family: control.pal.family
        font.pixelSize: 12
        font.weight: Font.ExtraBold
    }

    // Left / Right on a segment choose the neighbouring one and move the keyboard focus with it,
    // as in a group of radio buttons.
    function step(from, delta) {
        const index = Math.max(0, Math.min(model.length - 1, from + delta));
        if (index !== currentIndex) {
            activated(index);
        }
        const item = segments.itemAt(index);
        if (item) {
            item.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    Row {
        x: 3
        y: 3
        spacing: 3

        Repeater {
            id: segments
            model: control.model
            delegate: T.AbstractButton {
                id: segment
                required property int index
                required property string modelData
                readonly property bool chosen: index === control.currentIndex

                width: (control.textWidths[index] || 0) + control.share
                height: 28
                text: modelData
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus

                Accessible.role: Accessible.RadioButton
                Accessible.name: text
                Accessible.checked: chosen
                Accessible.onPressAction: segment.clicked()

                onClicked: control.activated(index)
                Keys.onLeftPressed: control.step(index, -1)
                Keys.onRightPressed: control.step(index, 1)

                background: Item {
                    Rectangle {
                        anchors.fill: parent
                        radius: 7
                        color: segment.chosen ? control.pal.accent
                            : segment.down ? control.pal.segmentBackground
                            : segment.hovered ? control.pal.segmentHover : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: Kirigami.Units.shortDuration
                            }
                        }
                    }
                    // Keyboard focus: a 2 px ring in the focus colour 1 px outside the segment (in
                    // the track's 3 px padding), so it also shows around the chosen segment.
                    Rectangle {
                        visible: segment.visualFocus
                        anchors.fill: parent
                        anchors.margins: -3
                        radius: 10
                        color: "transparent"
                        border.width: 2
                        border.color: control.pal.focusRing
                    }
                }
                contentItem: Item {
                    Text {
                        anchors.centerIn: parent
                        text: segment.text
                        font.family: control.pal.family
                        font.pixelSize: 12
                        font.weight: segment.chosen ? Font.ExtraBold : Font.DemiBold
                        color: segment.chosen ? control.pal.accentText : control.pal.label
                    }
                }
            }
        }
    }
}
