/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * The board's session pill (Login.dc.html, bottom left): the Fusion three-circle mark, the chosen
 * session's name and a chevron opening the list (sessionModel: name, exec, comment, lastIndex).
 * The name is read in the delegates (the model is a QAbstractItemModel; no get()).
 */

import QtQuick 2.15
import "palette.js" as Palette

Item {
    id: session
    width: pill.width
    height: 40
    property real maximumWidth: parent ? Math.max(0, parent.width - x - 32) : 240
    property real menuBottomLimit: y

    property int index: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property string selectedName: ""
    property bool resetting: false
    property bool busy: false
    readonly property bool valid: !resetting && index >= 0 && index < choices.count

    function syncSelection() {
        if (resetting) {
            return;
        }
        if (choices.count === 0) {
            index = -1;
            selectedName = "";
            return;
        }
        if (!valid) {
            index = 0;
        }
        const item = choices.itemAt(index);
        if (item) {
            selectedName = item.sessionName;
        }
    }

    // SDDM 0.21 declares count/lastIndex CONSTANT, but resets its model on directory changes.
    // Use the live Repeater count and discard cached selection/data (docs/parts/sddm.md).
    Connections {
        target: sessionModel
        function onModelAboutToBeReset() {
            session.resetting = true;
            session.index = -1;
            session.selectedName = "";
            if (menu.open) {
                session.closeMenu();
            }
        }
        function onModelReset() {
            session.resetting = false;
            Qt.callLater(session.syncSelection);
        }
        function onDataChanged() { Qt.callLater(session.syncSelection); }
    }
    Component.onCompleted: syncSelection()

    function choose(i, name) {
        if (busy) {
            return;
        }
        index = i;
        selectedName = name;
        menu.open = false;
        pill.forceActiveFocus();
    }
    function closeMenu() {
        menu.open = false;
        pill.forceActiveFocus();
    }
    function focusChoice(i) {
        if (choices.count > 0) {
            choices.itemAt((i + choices.count) % choices.count).forceActiveFocus();
        }
    }
    function revealChoice(item) {
        if (!item || viewport.height <= 0) {
            return;
        }
        const y = item.y;
        const wanted = y < viewport.contentY ? y
                     : Math.max(viewport.contentY, y + item.height - viewport.height);
        viewport.contentY = Math.max(0, Math.min(wanted, list.implicitHeight - viewport.height));
    }
    function toggleMenu() {
        if (busy) {
            return;
        }
        menu.open = !menu.open;
        if (menu.open) {
            focusChoice(session.index);
        } else {
            pill.forceActiveFocus();
        }
    }
    function openMenu() {
        if (busy) {
            return;
        }
        menu.open = true;
        focusChoice(session.index);
    }

    Rectangle {
        id: pill
        height: 40
        radius: 20
        color: Palette.fill
        border.color: activeFocus ? Palette.accent : Palette.stroke
        border.width: activeFocus ? 2 : 1
        width: Math.min(sessionLabel.implicitWidth + mark.width + chevron.implicitWidth + row.spacing * 2 + 26,
                        240, session.maximumWidth)
        Accessible.name: qsTr("Session: %1", "the chosen session's name").arg(session.selectedName)
        Accessible.role: Accessible.Button
        activeFocusOnTab: true
        Keys.onReturnPressed: session.toggleMenu()
        Keys.onEnterPressed: session.toggleMenu()
        Keys.onSpacePressed: session.toggleMenu()
        Accessible.onPressAction: session.toggleMenu()
        Keys.onDownPressed: session.openMenu()
        Keys.onUpPressed: session.openMenu()

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 10

            // The Fusion mark: three overlapping circles (the board's session logo)
            Item {
                id: mark
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                Rectangle { x: 3; y: 0; width: 11; height: 11; radius: 6; color: Palette.accent; opacity: 0.9 }
                Rectangle { x: 0; y: 6; width: 11; height: 11; radius: 6; color: "#f2a65a"; opacity: 0.9 }
                Rectangle { x: 8; y: 6; width: 11; height: 11; radius: 6; color: "#3cc4b0"; opacity: 0.85 }
            }
            Text {
                id: sessionLabel
                width: Math.max(0, pill.width - mark.width - chevron.implicitWidth - row.spacing * 2 - 26)
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
                font.family: Palette.bodyFont
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Palette.ink
                text: session.selectedName !== "" ? session.selectedName : qsTr("Session")
                textFormat: Text.PlainText
            }
            Text {
                id: chevron
                anchors.verticalCenter: parent.verticalCenter
                font.family: Palette.bodyFont
                font.pixelSize: 12
                color: Palette.inkSoft
                text: "\u25be"
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: session.toggleMenu()
        }
    }

    // The session list (the board's chevron menu)
    Rectangle {
        id: menu
        property bool open: false
        property int cursor: 0
        visible: open
        anchors.bottom: pill.top
        anchors.bottomMargin: 8 + Math.max(0, session.y - session.menuBottomLimit)
        anchors.left: pill.left
        width: Math.min(240, Math.max(0, session.parent.width - session.x - 32))
        height: Math.min(list.implicitHeight + 8,
                         Math.max(0, Math.min(session.y, session.menuBottomLimit) - 8 - 32))
        radius: 12
        color: "#f2141a2e"
        border.color: Palette.stroke
        border.width: 1

        Flickable {
            id: viewport
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            contentWidth: width
            contentHeight: list.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            onHeightChanged: {
                if (menu.open) {
                    session.revealChoice(choices.itemAt(menu.cursor));
                }
            }

            Column {
                id: list
                width: viewport.width
                Repeater {
                    id: choices
                    model: sessionModel
                    onCountChanged: Qt.callLater(session.syncSelection)
                    delegate: Rectangle {
                        id: choice
                        property string sessionName: String(model.name || "")
                        width: list.width
                        height: 32
                        radius: 8
                        color: session.index === index ? Palette.fill : "transparent"
                        border.color: Palette.accent
                        border.width: activeFocus ? 2 : 0

                        Accessible.name: String(model.name || "")
                        Accessible.role: Accessible.Button
                        Accessible.selected: session.index === index
                        activeFocusOnTab: true
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                menu.cursor = index;
                                session.revealChoice(choice);
                            }
                        }
                        Keys.onReturnPressed: session.choose(index, String(model.name || ""))
                        Keys.onEnterPressed: session.choose(index, String(model.name || ""))
                        Keys.onSpacePressed: session.choose(index, String(model.name || ""))
                        Accessible.onPressAction: session.choose(index, String(model.name || ""))
                        Keys.onDownPressed: session.focusChoice(index + 1)
                        Keys.onUpPressed: session.focusChoice(index - 1)
                        Keys.onEscapePressed: session.closeMenu()
                        Component.onCompleted: {
                            // The model's first answer names the pill (lastIndex, else the first)
                            if (session.selectedName === "" && index === session.index) {
                                session.selectedName = String(model.name || "");
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 12
                            width: parent.width - 24
                            elide: Text.ElideRight
                            font.family: Palette.bodyFont
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Palette.ink
                            text: String(model.name || "")
                            textFormat: Text.PlainText
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: session.choose(index, String(model.name || ""))
                        }
                    }
                }
            }
        }
    }
}
