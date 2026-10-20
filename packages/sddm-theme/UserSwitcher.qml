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

    Row {
        id: row
        spacing: 28

        Repeater {
            model: userModel
            delegate: Column {
                id: userColumn
                spacing: 8
                property bool selected: !switcher.otherSelected && switcher.selectedIndex === index

                Component.onCompleted: {
                    // The model's first answer picks the card's user (lastUser, else the first)
                    if (!switcher.sent && index === (userModel.lastIndex >= 0 ? userModel.lastIndex : 0)) {
                        switcher.sent = true;
                        switcher.userChosen(index, String(model.name), model.icon || "",
                                            String(model.realName || model.name),
                                            String(model.realName || model.name || "?").charAt(0).toUpperCase());
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
                    border.color: (selected || activeFocus) ? Palette.accent : Palette.avatarRing
                    border.width: (selected || activeFocus) ? 3 : 0

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
                        switcher.otherSelected = false;
                        switcher.selectedIndex = index;
                        switcher.userChosen(index, String(model.name), model.icon || "",
                                            String(model.realName || model.name),
                                            String(model.realName || model.name || "?").charAt(0).toUpperCase());
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: Palette.bodyFont
                    font.pixelSize: 13
                    font.weight: selected ? Font.ExtraBold : Font.DemiBold
                    color: selected ? Palette.ink : Palette.inkSoft
                    text: String(model.realName || model.name || "")
                }
            }
        }

        // "Other user": the board's dashed tile
        Column {
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
                border.color: (selected || activeFocus) ? Palette.accent : Palette.dashed
                border.width: (selected || activeFocus) ? 1.5 : 1.5

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
                    switcher.otherSelected = true;
                    switcher.otherRequested();
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
