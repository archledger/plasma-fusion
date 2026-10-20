/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * The board's user row (Login.dc.html, y 600): every user of userModel as a 56 px avatar with its
 * name, the selected one ringed in the accent, plus the "Other user" tile (the board's dashed
 * circle) for a user not in the model - as KDE's theme shows a username prompt.
 */

import QtQuick 2.15
import "palette.js" as Palette

Item {
    id: switcher
    width: row.width
    height: row.height

    property int selectedIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property bool otherSelected: false
    property bool sent: false
    property string selectedUser: ""
    property url selectedIcon: ""
    property string selectedName: ""
    property string selectedLetter: ""
    signal userChosen(int index, string user, url icon, string name, string letter)
    signal otherRequested()

    // Arrow keys move focus, Return/Space choose. Selecting an account focuses its password,
    // so arrows must not select it themselves or the next arrow would type into the password.
    readonly property int choiceCount: userModel.count + 1
    property int cursor: -1
    // Each delegate puts its row's data here (QAbstractItemModel has no get())
    property var rowsData: []
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
                                d ? d.name : "", d ? d.letter : "");
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

    Row {
        id: row
        spacing: 28

        Repeater {
            id: userRepeater
            model: userModel
            delegate: Column {
                id: userColumn
                spacing: 8
                property bool selected: !switcher.otherSelected && switcher.selectedIndex === index
                function focusChoice() { userTile.forceActiveFocus(); }

                Component.onCompleted: {
                    switcher.rowsData[index] = { "user": String(model.name), "icon": model.icon || "",
                        "name": String(model.realName || model.name),
                        "letter": String(model.realName || model.name || "?").charAt(0).toUpperCase() };
                    // The model's first answer picks the card's user (lastUser, else the first)
                    if (!switcher.sent && index === (userModel.lastIndex >= 0 ? userModel.lastIndex : 0)) {
                        switcher.sent = true;
                        switcher.userChosen(index, switcher.rowsData[index].user, switcher.rowsData[index].icon,
                                            switcher.rowsData[index].name, switcher.rowsData[index].letter);
                    }
                }

                Rectangle {
                    id: userTile
                    Accessible.name: String(model.realName || model.name || "")
                    Accessible.role: Accessible.Button
                    activeFocusOnTab: true
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56
                    height: 56
                    radius: 28
                    color: Palette.avatarFill
                    border.color: (userColumn.selected || activeFocus) ? Palette.accent : Palette.avatarRing
                    border.width: (userColumn.selected || activeFocus) ? 3 : 0
                    onActiveFocusChanged: { if (activeFocus) { switcher.cursor = index; } }
                    Keys.onLeftPressed: switcher.moveChoice(index, -1)
                    Keys.onRightPressed: switcher.moveChoice(index, 1)

                    CircularImage {
                        anchors.fill: parent
                        anchors.margins: 3
                        source: model.icon || ""
                        fill: Palette.avatarFill
                        visible: model.icon !== undefined && model.icon !== ""
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: model.icon === undefined || model.icon === ""
                        font.family: Palette.bodyFont
                        font.pixelSize: 22
                        font.weight: Font.ExtraBold
                        color: "#ffffff"
                        text: String(model.realName || model.name || "?").charAt(0).toUpperCase()
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: switchTo()
                    }
                    Keys.onReturnPressed: switchTo()
                    Keys.onEnterPressed: switchTo()
                    Keys.onSpacePressed: switchTo()
                    function switchTo() {
                        switcher.activateChoice(index);
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: Palette.bodyFont
                    font.pixelSize: 13
                    font.weight: userColumn.selected ? Font.ExtraBold : Font.DemiBold
                    color: userColumn.selected ? Palette.ink : Palette.inkSoft
                    text: String(model.realName || model.name || "")
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
                activeFocusOnTab: true
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56
                height: 56
                radius: 28
                color: Palette.fillField
                border.color: (otherColumn.selected || activeFocus) ? Palette.accent : Palette.dashed
                border.width: 1.5
                onActiveFocusChanged: { if (activeFocus) { switcher.cursor = userModel.count; } }
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
