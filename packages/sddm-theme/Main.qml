/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Plasma Fusion's SDDM login screen: design/boards/Login.dc.html at 1440 x 900. SDDM's greeter
 * hosts this Item in a QQuickView sized to the screen (GreeterApp.cpp: setResizeMode
 * SizeRootObjectToView, setGeometry per screen), so the layout anchors to the root and the board's
 * pixel values are kept as margins and sizes.
 *
 * SDDM provides the context objects this file uses (docs/THEMING.md, GreeterApp.cpp):
 *   sddm         hostName, canPowerOff/canReboot/canSuspend/canHibernate/canHybridSleep,
 *                powerOff()/reboot()/suspend()/hibernate(), login(user, password, sessionIndex),
 *                loginFailed/loginSucceeded/informationMessage signals
 *   userModel    name, realName, homeDir, icon, lastIndex, lastUser
 *   sessionModel name, exec, comment, lastIndex
 *   keyboard     the greeter's KeyboardModel: layouts[] (longName, shortName), currentLayout
 *   config       this theme's theme.conf ([General])
 * The models are QAbstractItemModel; rows are read in the delegates (no get()).
 */

import QtQuick 2.15

Rectangle {
    id: root
    color: "#0f1428"

    // The user the card shows (filled by UserSwitcher's delegates)
    property string personName: ""
    property url personIcon: ""
    property string personLetter: ""
    property string loginName: ""

    function login(user, password) {
        const who = user !== "" ? user : loginName;
        if (who === "") {
            return;
        }
        card.message = "";
        sddm.login(who, password, session.index);
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            card.message = qsTr("Wrong password");
            card.clearPassword();
        }
        function onInformationMessage(message) {
            card.message = message;
        }
    }

    // The pre-blurred Dusk Ridge treatment (generators/wallpapers: dusk-ridge-dark-login.png,
    // blur 20 px at scale 1.08 with the board's 50 % veil, baked into the image)
    Image {
        anchors.fill: parent
        source: config.background !== "" ? config.background
              : "/usr/share/plasma-fusion/backgrounds/dusk-ridge-dark-login.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    // ---- Top left: the clock and date (Space Grotesk 28/600, Manrope 14/700) ----
    Row {
        id: clockRow
        x: 32
        y: 28
        spacing: 12

        Text {
            id: clockText
            font.family: "Space Grotesk"
            font.pixelSize: 28
            font.weight: Font.DemiBold
            color: "#e8ebf4"
            text: Qt.formatTime(new Date(), "HH:mm")
            Timer {
                interval: 10000
                repeat: true
                running: true
                onTriggered: {
                    clockText.text = Qt.formatTime(new Date(), "HH:mm");
                    dateText.text = Qt.formatDate(new Date(), "dddd, d MMMM");
                }
            }
        }
        Text {
            id: dateText
            anchors.baseline: clockText.baseline
            font.family: "Manrope"
            font.pixelSize: 14
            font.weight: Font.Bold
            color: "#cdd3e4"
            text: Qt.formatDate(new Date(), "dddd, d MMMM")
        }
    }

    // ---- Top right: the keyboard pill (of the board's three pills only this has an API) ----
    Rectangle {
        id: keyboardPill
        visible: keyboard.layouts.length > 1
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 28
        anchors.rightMargin: 28
        width: Math.max(58, keyboardLabel.implicitWidth + 24)
        height: 34
        radius: 17
        color: "#14ffffff"
        Accessible.name: qsTr("Keyboard layout")

        Text {
            id: keyboardLabel
            anchors.centerIn: parent
            font.family: "Manrope"
            font.pixelSize: 12
            font.weight: Font.ExtraBold
            color: "#e8ebf4"
            text: {
                const l = keyboard.layouts[keyboard.currentLayout];
                return String(l && (l.shortName || l.longName) || "");
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
        }
    }

    // ---- The sign-in card (520,210 at 1440 x 900: centred, 400 wide) ----
    LoginCard {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 210 / 900)
        width: 400
        avatarSource: root.personIcon
        avatarLetter: root.personLetter
        personName: root.personName
        onLoginRequested: (user, password) => root.login(user, password)
    }

    // ---- The user row (y 600 of 900: two thirds down, centred) ----
    UserSwitcher {
        id: users
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 600 / 900)
        onUserChosen: (index, user, icon, name, letter) => {
            card.clearPassword();
            root.loginName = user;
            root.personIcon = icon;
            root.personName = name;
            root.personLetter = letter;
            card.promptName = false;
            card.focusPassword();
        }
        onOtherRequested: {
            card.clearPassword();
            root.loginName = "";
            root.personIcon = "";
            root.personName = "";
            root.personLetter = "?";
            card.promptName = true;
            card.focusPassword();
        }
    }

    Component.onCompleted: {
        if (!users.sent) {
            users.otherRequested();
        }
    }

    // ---- The session pill (bottom left) ----
    SessionPill {
        id: session
        x: 32
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
    }

    // ---- The power buttons (bottom right) ----
    PowerBar {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 32
        anchors.bottomMargin: 28
    }
}
