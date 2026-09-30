/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// Workspace indicator of the top bar pill (Main board): the current workspace is an 18x6 bar
// (radius 3, text colour), the others 6x6 dots at 40 % of the ink, 4 px apart. The bar grows
// and shrinks when the workspace changes. A click on a dot switches to that workspace, a click
// on the current one opens the Overview; Left/Right/Home/End work while it has keyboard focus.
//
// Each dot sits in a 2 px wider cell on both sides (hit area and the 4 px gap), so the visual
// group starts 2 px after the item's left edge.
FocusScope {
    id: dots

    required property int count
    required property int currentIndex
    required property var names
    required property color activeColor
    required property color inkColor
    required property color focusColor
    property int location: PlasmaCore.Types.TopEdge
    // Height of the cells (hit areas): the pill's height.
    property real cellHeight: 24
    // Touch: every dot's cell at least 24 px wide (ADAPTIVE 5.1).
    property bool touch: false
    required property Motion motion

    readonly property int cellPadding: 2

    signal switchRequested(int index)
    signal overviewRequested()

    implicitWidth: row.implicitWidth
    implicitHeight: cellHeight
    activeFocusOnTab: count > 1

    Accessible.role: Accessible.PageTabList
    Accessible.name: i18nc("@info accessible name, %1 current workspace number, %2 number of workspaces",
                           "Workspace %1 of %2", currentIndex + 1, count)

    function nameOf(index: int): string {
        const name = index >= 0 && index < names.length ? names[index] : "";
        return name ? String(name) : i18nc("@info workspace without a name, %1 its number", "Workspace %1", index + 1);
    }

    Keys.onPressed: event => {
        let target = -1;
        const forward = Application.layoutDirection === Qt.RightToLeft ? Qt.Key_Left : Qt.Key_Right;
        const backward = Application.layoutDirection === Qt.RightToLeft ? Qt.Key_Right : Qt.Key_Left;
        if (event.key === forward) {
            target = Math.min(count - 1, currentIndex + 1);
        } else if (event.key === backward) {
            target = Math.max(0, currentIndex - 1);
        } else if (event.key === Qt.Key_Home) {
            target = 0;
        } else if (event.key === Qt.Key_End) {
            target = count - 1;
        } else if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select].indexOf(event.key) !== -1) {
            dots.overviewRequested();
            event.accepted = true;
            return;
        } else {
            return;
        }
        event.accepted = true;
        if (target !== currentIndex && target >= 0) {
            dots.switchRequested(target);
        }
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            model: dots.count

            delegate: PlasmaCore.ToolTipArea {
                id: cell

                required property int index
                readonly property bool current: index === dots.currentIndex

                width: dots.touch ? Math.max(24, dot.width + 2 * dots.cellPadding) : dot.width + 2 * dots.cellPadding
                height: dots.implicitHeight
                mainText: dots.nameOf(index)
                subText: i18nc("@info:tooltip %1 workspace number, %2 number of workspaces",
                               "Workspace %1 of %2", index + 1, dots.count)
                location: dots.location

                Accessible.role: Accessible.PageTab
                Accessible.name: mainText
                Accessible.selected: current

                Rectangle {
                    id: dot
                    anchors.centerIn: parent
                    width: cell.current ? 18 : 6
                    height: 6
                    radius: 3
                    antialiasing: true
                    color: cell.current ? dots.activeColor
                         : Qt.rgba(dots.inkColor.r, dots.inkColor.g, dots.inkColor.b, area.containsMouse ? 0.7 : 0.4)

                    Behavior on width {
                        enabled: dots.motion.animate
                        NumberAnimation {
                            duration: dots.motion.toggle
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on color {
                        enabled: dots.motion.animate
                        ColorAnimation { duration: dots.motion.toggle }
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: cell.current ? dots.overviewRequested() : dots.switchRequested(cell.index)
                }
            }
        }
    }

    // Keyboard focus: 2 px ring 2 px outside the dots.
    Rectangle {
        visible: dots.activeFocus
        x: dots.cellPadding - 4
        anchors.verticalCenter: parent.verticalCenter
        width: row.width - 2 * dots.cellPadding + 8
        height: 6 + 8
        radius: 7
        color: "transparent"
        border.width: 2
        border.color: dots.focusColor
    }
}
