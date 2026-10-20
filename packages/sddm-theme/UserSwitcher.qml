/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * The board's user row (Login.dc.html, y 600): every user of userModel as a 56 px avatar with its
 * name, the selected one ringed in the accent, plus the "Other user" tile (the board's dashed
 * circle) for a user not in the model - as KDE's theme shows a username prompt.
 */

import QtQuick 2.15
import "palette.js" as Palette

Flickable {
    id: switcher
    width: Math.min(row.width, Math.max(0, maximumWidth))
    height: row.height
    property real maximumWidth: parent ? Math.max(0, parent.width - 64) : 1440
    onWidthChanged: Qt.callLater(revealSelection)
    clip: true
    contentWidth: row.width
    contentHeight: row.height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds

    property int selectedIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property bool otherSelected: false
    property bool sent: false
    property string selectedUser: ""
    property url selectedIcon: ""
    property string selectedName: ""
    property string selectedLetter: ""
    signal userChosen(int index, string user, url icon, string name, string letter, bool needsPassword)
    signal otherRequested()

    // Arrow keys move focus, Return/Space choose. Selecting an account focuses its password,
    // so arrows must not select it themselves or the next arrow would type into the password.
    readonly property int choiceCount: userModel.count + 1
    property int cursor: -1
    // Each delegate puts its row's data here (QAbstractItemModel has no get())
    property var rowsData: []
    // Real names are not unique; duplicates need the login name in their identity.
    property var nameCounts: ({})
    function recountNames() {
        const counts = {};
        for (let i = 0; i < rowsData.length; ++i) {
            const d = rowsData[i];
            if (d) {
                counts[d.name] = (counts[d.name] || 0) + 1;
            }
        }
        nameCounts = counts;
    }
    function displayNameFor(i) {
        const d = rowsData[i];
        if (!d) {
            return "";
        }
        if ((nameCounts[d.name] || 0) > 1 && d.user !== d.name) {
            return d.name + " (" + d.user + ")";
        }
        return d.name;
    }
    function selectInitial() {
        if (sent) {
            return;
        }
        sent = true;
        otherSelected = false;
        const d = rowsData[selectedIndex];
        if (!d) {
            return;
        }
        userChosen(selectedIndex, d.user, d.icon, displayNameFor(selectedIndex),
                   d.letter, d.needsPassword);
        Qt.callLater(revealSelection);
    }
    function activateChoice(i) {
        cursor = i;
        if (i === userModel.count) {
            otherSelected = true;
            otherRequested();
        } else {
            otherSelected = false;
            selectedIndex = i;
            const d = switcher.rowsData[i];
            switcher.userChosen(i, d ? d.user : "", d ? d.icon : "",
                                switcher.displayNameFor(i), d ? d.letter : "",
                                d ? d.needsPassword : true);
        }
    }
    function moveChoice(from, delta) {
        const next = (from + delta + choiceCount) % choiceCount;
        if (next === userModel.count) {
            otherTile.forceActiveFocus();
        } else {
            userRepeater.itemAt(next).focusChoice();
        }
    }
    function ensureVisible(item) {
        if (!item || switcher.width <= 0) {
            return;
        }
        const x = item.mapToItem(row, 0, 0).x;
        const wanted = x < switcher.contentX ? x
                     : Math.max(switcher.contentX, x + item.width - switcher.width);
        switcher.contentX = Math.max(0, Math.min(wanted, row.width - switcher.width));
    }
    function revealSelection() {
        ensureVisible(otherSelected ? otherTile : userRepeater.itemAt(selectedIndex));
    }

    Row {
        id: row
        spacing: 28

        Repeater {
            id: userRepeater
            model: userModel
            delegate: Column {
                id: userColumn
                width: 56
                spacing: 8
                property bool selected: !switcher.otherSelected && switcher.selectedIndex === index
                readonly property bool duplicateName: (switcher.nameCounts[String(model.realName || model.name)] || 0) > 1
                readonly property bool nameDiffers: String(model.realName || "") !== ""
                    && String(model.realName) !== String(model.name)
                readonly property string shownName: switcher.displayNameFor(index)
                // A 56 px caption elides any suffix; for duplicate real names show the login name,
                // which is short enough to remain the visible distinguishing identifier.
                readonly property string caption: duplicateName && nameDiffers
                    ? String(model.name || "") : shownName
                function focusChoice() { userTile.forceActiveFocus(); }

                Component.onCompleted: {
                    const rows = switcher.rowsData.slice();
                    rows[index] = { "user": String(model.name), "icon": model.icon || "",
                        "name": String(model.realName || model.name),
                        "letter": String(model.realName || model.name || "?").charAt(0).toUpperCase(),
                        "needsPassword": model.needsPassword === undefined ? true : model.needsPassword };
                    // A new array notifies the shownName bindings; mutating an element does not.
                    switcher.rowsData = rows;
                    Qt.callLater(switcher.recountNames);
                    // The model's first answer picks the card's user (lastUser, else the first).
                    // Deferred so duplicate real names are known before the identity is shown.
                    if (!switcher.sent && index === (userModel.lastIndex >= 0 ? userModel.lastIndex : 0)) {
                        Qt.callLater(switcher.selectInitial);
                    }
                }

                Rectangle {
                    id: userTile
                    Accessible.name: userColumn.shownName
                    Accessible.role: Accessible.Button
                    Accessible.selected: userColumn.selected
                    activeFocusOnTab: true
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56
                    height: 56
                    radius: 28
                    color: Palette.avatarFill
                    border.color: (userColumn.selected || activeFocus) ? Palette.accent : Palette.avatarRing
                    border.width: (userColumn.selected || activeFocus) ? 3 : 0
                    onActiveFocusChanged: {
                        if (activeFocus) {
                            switcher.cursor = index;
                            switcher.ensureVisible(userColumn);
                        }
                    }
                    Keys.onLeftPressed: switcher.moveChoice(index, -1)
                    Keys.onRightPressed: switcher.moveChoice(index, 1)

                    CircularImage {
                        id: tileAvatar
                        anchors.fill: parent
                        anchors.margins: 3
                        source: model.icon || ""
                        fill: Palette.avatarFill
                        visible: model.icon !== undefined && model.icon !== ""
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !tileAvatar.ready
                        font.family: Palette.bodyFont
                        font.pixelSize: 22
                        font.weight: Font.ExtraBold
                        color: "#ffffff"
                        text: String(model.realName || model.name || "?").charAt(0).toUpperCase()
                        textFormat: Text.PlainText
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: switchTo()
                    }
                    Keys.onReturnPressed: switchTo()
                    Keys.onEnterPressed: switchTo()
                    Keys.onSpacePressed: switchTo()
                    Accessible.onPressAction: switchTo()
                    function switchTo() {
                        switcher.activateChoice(index);
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.family: Palette.bodyFont
                    font.pixelSize: 13
                    font.weight: userColumn.selected ? Font.ExtraBold : Font.DemiBold
                    color: userColumn.selected ? Palette.ink : Palette.inkSoft
                    text: userColumn.caption
                    textFormat: Text.PlainText
                }
            }
        }

        // "Other user": the board's dashed tile
        Column {
            id: otherColumn
            spacing: 8
            property bool selected: switcher.otherSelected

            Rectangle {
                id: otherTile
                Accessible.name: qsTr("Other user")
                Accessible.role: Accessible.Button
                Accessible.selected: otherColumn.selected
                activeFocusOnTab: true
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56
                height: 56
                radius: 28
                color: Palette.fillField
                border.color: (otherColumn.selected || activeFocus) ? Palette.accent : Palette.dashed
                border.width: 1.5
                onActiveFocusChanged: {
                    if (activeFocus) {
                        switcher.cursor = userModel.count;
                        switcher.ensureVisible(otherColumn);
                    }
                }
                Keys.onLeftPressed: switcher.moveChoice(userModel.count, -1)
                Keys.onRightPressed: switcher.moveChoice(userModel.count, 1)

                Item {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        width: 11
                        height: 11
                        radius: 6
                        color: "transparent"
                        border.color: Palette.ink
                        border.width: 1.8
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: 22
                        height: 12
                        radius: 6
                        color: "transparent"
                        border.color: Palette.ink
                        border.width: 1.8
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: switchToOther()
                }
                Keys.onReturnPressed: switchToOther()
                Keys.onEnterPressed: switchToOther()
                Keys.onSpacePressed: switchToOther()
                Accessible.onPressAction: switchToOther()
                function switchToOther() {
                    switcher.activateChoice(userModel.count);
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Palette.bodyFont
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Palette.inkSoft
                text: qsTr("Other user")
            }
        }
    }

    // The first user is the card's until the model answers (see the delegate's onCompleted)
}
