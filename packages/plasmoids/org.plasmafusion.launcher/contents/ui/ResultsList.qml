/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

import "../code/launcher.js" as Launcher

// KRunner results (merged RunnerModel) as 48 px rows grouped by category.
ListView {
    id: list

    property FusionColors pal
    property string fontFamily
    property var launcher
    property bool keyboardNavigation: false
    // Hover selects only after the pointer really moved, not when results appear under a
    // resting pointer (Enter must launch the top result then).
    property bool pointerActive: false
    property point lastPointer: Qt.point(NaN, NaN)

    signal exitTop()
    // Printable text typed while the list has focus; "\b" for Backspace.
    signal typed(string text)

    function resetPointer() {
        pointerActive = false;
        lastPointer = Qt.point(NaN, NaN);
    }

    function pointerMovedTo(item: Item, x: real, y: real): bool {
        const p = item.mapToItem(null, x, y);
        const moved = !isNaN(lastPointer.x) && (Math.abs(p.x - lastPointer.x) >= 1 || Math.abs(p.y - lastPointer.y) >= 1);
        lastPointer = Qt.point(p.x, p.y);
        if (moved) {
            pointerActive = true;
        }
        return moved;
    }

    clip: true
    currentIndex: count > 0 ? 0 : -1
    boundsBehavior: Flickable.StopAtBounds
    highlightFollowsCurrentItem: false
    keyNavigationEnabled: true
    reuseItems: true
    spacing: 2
    Accessible.role: Accessible.List

    T.ScrollBar.vertical: ThinScrollBar {
        pal: list.pal
        visible: size < 1.0
    }

    section.property: "group"
    section.criteria: ViewSection.FullString
    section.delegate: Item {
        required property string section
        width: ListView.view.width
        height: 30

        FusionText {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            text: parent.section
            color: list.pal.muted
            family: list.fontFamily
            px: 12
            weight: 800
        }
    }

    function launch(index: int) {
        if (!model || index < 0 || index >= count) {
            return;
        }
        if (model.trigger(index, "", null) && launcher) {
            launcher.close();
        }
    }

    delegate: Item {
        id: resultRow

        required property int index
        required property var model

        readonly property bool isCurrent: ListView.isCurrentItem

        width: ListView.view.width - 10
        height: 48

        Accessible.role: Accessible.Button
        Accessible.name: model.display || ""
        Accessible.description: model.description || ""

        Rectangle {
            anchors.fill: parent
            radius: 12
            antialiasing: true
            color: (mouse.containsMouse && list.pointerActive) || resultRow.isCurrent ? list.pal.tileHover : "transparent"

            FocusRing {
                anchors.margins: 0
                radius: 12
                visible: resultRow.isCurrent && list.activeFocus && list.keyboardNavigation
                ringColor: list.pal.focusRing
            }
        }

        Kirigami.Icon {
            id: resultIcon
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            source: resultRow.model.decoration || "application-x-executable"
            animated: false
        }

        Column {
            anchors.left: resultIcon.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            FusionText {
                width: parent.width
                text: resultRow.model.display || ""
                elide: Text.ElideRight
                maximumLineCount: 1
                color: list.pal.text
                family: list.fontFamily
                px: 13
                weight: 700
            }

            FusionText {
                width: parent.width
                visible: text.length > 0
                text: {
                    const d = String(resultRow.model.description || "");
                    return d.length > 0 ? d.replace(/\n/g, " ") : "";
                }
                elide: Text.ElideRight
                maximumLineCount: 1
                color: list.pal.muted
                family: list.fontFamily
                px: 11.5
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPositionChanged: mouseEvent => {
                if (list.pointerMovedTo(mouse, mouseEvent.x, mouseEvent.y)) {
                    list.keyboardNavigation = false;
                    list.currentIndex = resultRow.index;
                }
            }
            onClicked: mouseEvent => {
                if (mouseEvent.button === Qt.RightButton) {
                    list.currentIndex = resultRow.index;
                    if (list.launcher) {
                        list.launcher.openActionMenu(list.model, resultRow.index, resultRow.model, resultRow, mouseEvent.x, mouseEvent.y);
                    }
                } else {
                    list.launch(resultRow.index);
                }
            }
        }
    }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Up:
            keyboardNavigation = true;
            pointerActive = false;
            if (currentIndex <= 0) {
                exitTop();
                event.accepted = true;
            }
            break;
        case Qt.Key_Down:
        case Qt.Key_PageUp:
        case Qt.Key_PageDown:
        case Qt.Key_Home:
        case Qt.Key_End:
            keyboardNavigation = true;
            pointerActive = false;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            launch(currentIndex);
            event.accepted = true;
            break;
        case Qt.Key_Menu:
            if (currentItem && launcher) {
                launcher.openActionMenu(model, currentIndex, currentItem.model, currentItem, 24, currentItem.height / 2);
            }
            event.accepted = true;
            break;
        case Qt.Key_Backspace:
            typed("\b");
            event.accepted = true;
            break;
        default:
            // Escape and other keys without printable text go on to the card.
            if (Launcher.isPrintable(event.text) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                typed(event.text);
                event.accepted = true;
            }
            break;
        }
    }
}
