/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

import "../code/launcher.js" as Launcher

// KRunner results (merged RunnerModel) as 48 px rows grouped by category. Row and header
// heights, text and the paddings next to it follow the user's text size; icons keep their size.
// The last row hands the query to the full KRunner (all its plugins, web shortcuts too), as
// Kickoff does when its own results end: Down past the last result, then Enter, or a click.
ListView {
    id: list

    property FusionColors pal
    property FusionMetrics metrics
    property var launcher
    property bool keyboardNavigation: false
    // Hover selects only after the pointer really moved, not when results appear under a
    // resting pointer (Enter must launch the top result then).
    property bool pointerActive: false
    property point lastPointer: Qt.point(NaN, NaN)
    // The query, and whether the hand-off row below the results is the current row.
    readonly property string query: launcher ? String(launcher.searchText || "") : ""
    readonly property bool handoffShown: query.trim().length > 0
    property bool handoffCurrent: false
    onQueryChanged: handoffCurrent = false

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
    spacing: metrics.px(2)
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
        height: list.metrics.px(30)

        FusionText {
            anchors.left: parent.left
            anchors.leftMargin: list.metrics.px(10)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: list.metrics.px(6)
            text: parent.section
            color: list.pal.muted
            metrics: list.metrics
            px: 12
            weight: 800
        }
    }

    function openInKRunner() {
        if (launcher && handoffShown) {
            launcher.searchInKRunner(query);
        }
    }

    // The keyboard selection on the hand-off row (Down from the search field when there are no
    // results).
    function selectHandoff() {
        if (handoffShown) {
            handoffCurrent = true;
            keyboardNavigation = true;
            pointerActive = false;
            positionViewAtEnd();
        }
    }

    // Home, End, Page Up and Page Down. A page is as many rows as the list shows; Page Down on the
    // last result, and End, reach the hand-off row, which is the last row.
    function pageKey(key: int): void {
        const atLast = handoffCurrent || count === 0 || currentIndex >= count - 1;
        if (key === Qt.Key_End || (key === Qt.Key_PageDown && atLast)) {
            if (handoffShown) {
                selectHandoff();
            } else if (count > 0) {
                currentIndex = count - 1;
                positionViewAtIndex(currentIndex, ListView.Contain);
            }
            return;
        }
        if (count === 0) {
            return;
        }
        const rowHeight = currentItem ? currentItem.height + spacing : metrics.px(48);
        const page = Math.max(1, Math.floor(height / Math.max(1, rowHeight)));
        let target = 0;
        if (key === Qt.Key_PageUp) {
            target = handoffCurrent ? count - 1 : Math.max(0, currentIndex - page);
        } else if (key === Qt.Key_PageDown) {
            target = Math.min(count - 1, currentIndex + page);
        }
        handoffCurrent = false;
        currentIndex = target;
        positionViewAtIndex(currentIndex, ListView.Contain);
    }

    function launch(index: int) {
        if (handoffCurrent) {
            openInKRunner();
            return;
        }
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

        readonly property bool isCurrent: ListView.isCurrentItem && !list.handoffCurrent

        width: ListView.view.width - 10
        height: list.metrics.px(48)

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
            x: list.metrics.px(10)
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            source: resultRow.model.decoration || "application-x-executable"
            animated: false
        }

        Column {
            anchors.left: resultIcon.right
            anchors.leftMargin: list.metrics.px(12)
            anchors.right: parent.right
            anchors.rightMargin: list.metrics.px(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: list.metrics.px(2)

            FusionText {
                width: parent.width
                text: resultRow.model.display || ""
                elide: Text.ElideRight
                maximumLineCount: 1
                color: list.pal.text
                metrics: list.metrics
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
                metrics: list.metrics
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
                    list.handoffCurrent = false;
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

    // No results (and the query is done): a line above the hand-off row.
    header: Item {
        width: ListView.view.width - 10
        height: noResults.visible ? noResults.implicitHeight + list.metrics.px(56) : 0

        FusionText {
            id: noResults
            anchors.horizontalCenter: parent.horizontalCenter
            y: list.metrics.px(40)
            width: parent.width - 50
            visible: list.count === 0 && list.handoffShown && list.launcher !== null && list.launcher !== undefined
                     && !list.launcher.runnerModel.querying
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: i18nc("@info", "No results for “%1”", list.query)
            color: list.pal.muted
            metrics: list.metrics
            px: 13
        }
    }

    footer: Item {
        id: handoff
        width: ListView.view.width - 10
        height: list.handoffShown ? list.metrics.px(48) + list.metrics.px(8) : 0
        visible: list.handoffShown

        readonly property bool hovered: handoffMouse.containsMouse && list.pointerActive

        Accessible.role: Accessible.Button
        Accessible.name: handoffTitle.text
        Accessible.description: handoffSubtitle.text
        Accessible.onPressAction: list.openInKRunner()

        Rectangle {
            y: list.metrics.px(8)
            width: parent.width
            height: parent.height - y
            radius: 12
            antialiasing: true
            color: handoff.hovered || list.handoffCurrent ? list.pal.tileHover : "transparent"

            FocusRing {
                anchors.margins: 0
                radius: 12
                visible: list.handoffCurrent && list.activeFocus && list.keyboardNavigation
                ringColor: list.pal.focusRing
            }

            Kirigami.Icon {
                id: handoffIcon
                x: list.metrics.px(10)
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                source: "plasma-search"
                animated: false
            }

            Column {
                anchors.left: handoffIcon.right
                anchors.leftMargin: list.metrics.px(12)
                anchors.right: parent.right
                anchors.rightMargin: list.metrics.px(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: list.metrics.px(2)

                FusionText {
                    id: handoffTitle
                    width: parent.width
                    text: i18nc("@action:button %1 is the search text", "Search “%1” in KRunner", list.query.trim())
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: list.pal.text
                    metrics: list.metrics
                    px: 13
                    weight: 700
                }
                FusionText {
                    id: handoffSubtitle
                    width: parent.width
                    text: i18nc("@info", "Every search plugin, web shortcuts included")
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: list.pal.muted
                    metrics: list.metrics
                    px: 11.5
                }
            }

            MouseArea {
                id: handoffMouse
                anchors.fill: parent
                hoverEnabled: true
                Accessible.name: handoffTitle.text
                onPositionChanged: mouseEvent => {
                    if (list.pointerMovedTo(handoffMouse, mouseEvent.x, mouseEvent.y)) {
                        list.keyboardNavigation = false;
                        list.handoffCurrent = true;
                    }
                }
                onClicked: list.openInKRunner()
            }
        }
    }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Up:
            keyboardNavigation = true;
            pointerActive = false;
            if (handoffCurrent) {
                handoffCurrent = false;
                if (count === 0) {
                    exitTop();
                } else {
                    positionViewAtIndex(currentIndex, ListView.Contain);
                }
                event.accepted = true;
            } else if (currentIndex <= 0) {
                exitTop();
                event.accepted = true;
            }
            break;
        case Qt.Key_Down:
            keyboardNavigation = true;
            pointerActive = false;
            if (handoffShown && (count === 0 || currentIndex >= count - 1)) {
                selectHandoff();
                event.accepted = true;
            }
            break;
        case Qt.Key_PageUp:
        case Qt.Key_PageDown:
        case Qt.Key_Home:
        case Qt.Key_End:
            // ListView itself moves only with the arrows; these keys work as in Kickoff's lists.
            // The hand-off row is the last row: End goes there, Home and Page Up leave it, so the
            // row that looks selected is the one Enter opens.
            keyboardNavigation = true;
            pointerActive = false;
            pageKey(event.key);
            event.accepted = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            launch(currentIndex);
            event.accepted = true;
            break;
        case Qt.Key_Menu:
            if (currentItem && launcher && !handoffCurrent) {
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
