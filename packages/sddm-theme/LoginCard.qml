/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * The board's sign-in card (Login.dc.html, 520,210 at 1440 x 900): the 112 px avatar, the name,
 * the 340 x 28 pill password field with its show-password and sign-in buttons, and the message
 * row. "Use fingerprint" and "Caps Lock is on" are board items SDDM gives themes no API for
 * (GreeterProxy.h); the message slot carries login messages instead (docs/parts/sddm.md).
 */

import QtQuick 2.15
import "palette.js" as Palette

Item {
    id: card
    height: column.implicitHeight

    property url avatarSource: ""
    property string avatarLetter: ""
    property string personName: ""
    property bool promptName: false
    property string message: ""
    signal loginRequested(string user, string password)

    function focusPassword() {
        if (promptName) {
            nameInput.forceActiveFocus();
        } else {
            password.forceActiveFocus();
        }
    }
    function clearPassword() {
        showPassword.pressed = false;
        password.text = "";
        password.forceActiveFocus();
    }

    Column {
        id: column
        width: parent.width
        spacing: 16

        // Avatar: the user's icon, else its initial on the board's purple disc
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 112
            height: 112
            radius: 56
            color: Palette.avatarFill
            border.color: Palette.avatarRing
            border.width: 4

            CircularImage {
                anchors.fill: parent
                anchors.margins: 4
                source: card.avatarSource
                fill: Palette.avatarFill
                visible: card.avatarSource != ""
            }
            Text {
                anchors.centerIn: parent
                visible: card.avatarSource == ""
                font.family: Palette.clockFont
                font.pixelSize: 46
                font.weight: Font.Bold
                color: "#ffffff"
                text: card.avatarLetter
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: Palette.clockFont
            font.pixelSize: 28
            font.weight: Font.DemiBold
            color: Palette.ink
            text: card.personName
            visible: !card.promptName
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 340
            spacing: 10

            // The name field (the "Other user" path; as KDE's theme: a user not in the model)
            Rectangle {
                id: nameRow
                visible: card.promptName
                width: parent.width
                height: 48
                radius: 24
                color: Palette.fillField
                border.color: nameInput.activeFocus ? Palette.accent : Palette.stroke
                border.width: nameInput.activeFocus ? 1.5 : 1

                Rectangle {
                    visible: nameInput.activeFocus
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: 28
                    color: "transparent"
                    border.color: Palette.accentRing
                    border.width: 4
                    z: -1
                }
                TextInput {
                    id: nameInput
                    Accessible.name: qsTr("Username")
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Palette.bodyFont
                    font.pixelSize: 16
                    color: Palette.ink
                    clip: true
                    onAccepted: password.forceActiveFocus()
                }
                Text {
                    anchors.fill: nameInput
                    verticalAlignment: Text.AlignVCenter
                    font.family: Palette.bodyFont
                    font.pixelSize: 16
                    color: Palette.inkMuted
                    visible: nameInput.text === "" && nameInput.preeditText.length === 0
                    text: qsTr("Username")
                }
            }

            // The pill password field (48 high, radius 24, the accent ring when focused)
            Rectangle {
                id: passwordRow
                width: parent.width
                height: 48
                radius: 24
                color: Palette.fillField
                border.color: password.activeFocus ? Palette.accent : Palette.stroke
                border.width: password.activeFocus ? 1.5 : 1

                Rectangle {
                    visible: password.activeFocus
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: 28
                    color: "transparent"
                    border.color: Palette.accentRing
                    border.width: 4
                    z: -1
                }

                TextInput {
                    id: password
                    Accessible.name: qsTr("Password")
                    anchors.left: parent.left
                    anchors.right: showPassword.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Palette.bodyFont
                    font.pixelSize: 16
                    font.letterSpacing: 0.2
                    color: Palette.ink
                    echoMode: showPassword.pressed ? TextInput.Normal : TextInput.Password
                    clip: true
                    onAccepted: card.loginRequested(card.promptName ? nameInput.text : "", text)
                    Keys.onEscapePressed: card.clearPassword()
                    Keys.onPressed: event => {
                        // Match the lock screen: deleted input must not be recoverable after reveal.
                        if (event.matches(StandardKey.Undo) || event.matches(StandardKey.Redo)) {
                            event.accepted = true;
                        }
                    }
                }
                Text {
                    anchors.fill: password
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Palette.bodyFont
                    font.pixelSize: 16
                    color: Palette.inkMuted
                    visible: password.text === "" && password.preeditText.length === 0
                    text: qsTr("Password")
                }

                // Show password (the board's eye; 36 px round, inkSoft)
                Item {
                    id: showPassword
                    Accessible.name: qsTr("Show password")
                    Accessible.role: Accessible.Button
                    activeFocusOnTab: true
                    property bool pressed: false
                    Keys.onReturnPressed: pressed = !pressed
                    Keys.onEnterPressed: pressed = !pressed
                    Keys.onSpacePressed: pressed = !pressed
                    anchors.right: signIn.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36

                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: "transparent"
                        border.color: Palette.accent
                        border.width: showPassword.activeFocus ? 2 : 0
                    }

                    // The eye: a lens, its pupil and a struck line while the text shows
                    Item {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        Rectangle {
                            anchors.centerIn: parent
                            width: 18
                            height: 11
                            radius: 6
                            color: "transparent"
                            border.color: Palette.inkSoft
                            border.width: 1.8
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            radius: 3
                            color: "transparent"
                            border.color: Palette.inkSoft
                            border.width: 1.8
                        }
                        Rectangle {
                            visible: showPassword.pressed
                            anchors.centerIn: parent
                            width: 22
                            height: 2
                            color: Palette.inkSoft
                            rotation: -45
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: showPassword.pressed = !showPassword.pressed
                    }
                }

                // Sign in (36 px round, the board's deep blue arrow)
                Rectangle {
                    id: signIn
                    Accessible.name: qsTr("Sign in")
                    Accessible.role: Accessible.Button
                    activeFocusOnTab: true
                    Keys.onReturnPressed: card.loginRequested(card.promptName ? nameInput.text : "", password.text)
                    Keys.onEnterPressed: card.loginRequested(card.promptName ? nameInput.text : "", password.text)
                    Keys.onSpacePressed: card.loginRequested(card.promptName ? nameInput.text : "", password.text)
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: 18
                    color: Palette.accentDeep
                    border.color: Palette.accent
                    border.width: activeFocus ? 2 : 0

                    Item {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            height: 1.8
                            color: "#ffffff"
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 1.8
                            color: "#ffffff"
                            rotation: 45
                            transformOrigin: Item.Right
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 1.8
                            color: "#ffffff"
                            rotation: -45
                            transformOrigin: Item.Right
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: card.loginRequested(card.promptName ? nameInput.text : "", password.text)
                    }
                }
            }

            // The message row (the board's caps-lock/fingerprint row; the fingerprint link is the
            // one board item SDDM gives themes no API for - docs/parts/sddm.md)
            Column {
                width: parent.width
                spacing: 4

                Row {
                    visible: keyboard.capsLock
                    spacing: 6
                    Canvas {
                        width: 14
                        height: 14
                        anchors.verticalCenter: parent.verticalCenter
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            ctx.fillStyle = Palette.warnInk;
                            // The board's bolt (M12 4l7 8h-4v7H9v-7H5z at 24 -> 14)
                            ctx.beginPath();
                            ctx.moveTo(8.2, 2.3);
                            ctx.lineTo(12.3, 6.9);
                            ctx.lineTo(9.9, 6.9);
                            ctx.lineTo(9.9, 11.7);
                            ctx.lineTo(5.8, 6.9);
                            ctx.lineTo(8.2, 6.9);
                            ctx.closePath();
                            ctx.fill();
                        }
                        Component.onCompleted: requestPaint()
                    }
                    Text {
                        font.family: Palette.bodyFont
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Palette.warnInk
                        text: qsTr("Caps Lock is on")
                    }
                }

                Text {
                    width: parent.width
                    visible: card.message !== ""
                    font.family: Palette.bodyFont
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: Palette.warnInk
                    text: card.message
                    elide: Text.ElideRight
                }
            }
        }
    }
}
