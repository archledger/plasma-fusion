/*
    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.config as KConfig
import org.kde.kscreenlocker as ScreenLocker
import org.kde.breeze.components

// The unlock prompt, styled after the Login board: avatar and name, the 340 px password pill
// (reveal and unlock buttons inside), the "Caps Lock is on" / "Use fingerprint" line, the PAM
// message area and the Sleep / Hibernate / Switch user buttons along the bottom edge.
//
// Same interface as the Plasma lock screen's MainBlock: mainPasswordBox, showPassword,
// lockScreenUiVisible, notificationMessage, actionItems, visibleBoundary (for the virtual
// keyboard), passwordResult(), playHighlightAnimation().
FocusScope {
    id: sessionManager

    // LockScreen.qml's root item: clearPassword() and notificationRepeated() come from there.
    property var lockRoot: null
    // The PamAuthenticators object (context property "authenticator").
    property QtObject authenticatorObject: null

    readonly property alias mainPasswordBox: passwordBox
    property bool lockScreenUiVisible: false
    property alias showPassword: passwordBox.showPassword
    property alias notificationMessage: messageLabel.text
    property alias actionItems: actionRow.children
    property var userListModel
    property string userName: ""
    property url userIcon: ""
    property bool capsLockOn: false

    // qmllint disable missing-property
    readonly property int authenticatorTypes: authenticatorObject ? authenticatorObject.authenticatorTypes : 0
    // qmllint enable missing-property
    readonly property bool fingerprintAvailable: (authenticatorTypes & ScreenLocker.Authenticator.Fingerprint) !== 0
    readonly property bool smartcardAvailable: (authenticatorTypes & ScreenLocker.Authenticator.Smartcard) !== 0

    // The y position that has to stay visible above the on-screen keyboard.
    property int visibleBoundary: card.y + form.y + pill.y + pill.height + Kirigami.Units.largeSpacing
    // Bottom of the prompt (avatar to message area) and top of the power buttons.
    readonly property real contentBottom: card.y + card.height
    readonly property real actionsTop: actionRow.visibleChildren.length > 0 ? actionRow.y : height

    signal passwordResult(string password)
    signal userSelected()

    function startLogin() {
        const password = passwordBox.text;
        // Moving the focus away first works round a Qt bug that can trigger if the app is
        // closed with a TextField focused (QTBUG-55460).
        loginButton.forceActiveFocus();
        passwordResult(password);
    }

    function playHighlightAnimation() {
        bounceAnimation.start();
    }

    Column {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(Kirigami.Units.gridUnit, Math.round(sessionManager.height * 210 / PfStyle.boardHeight))
        width: 400
        spacing: 22

        UserHeader {
            anchors.horizontalCenter: parent.horizontalCenter
            userName: sessionManager.userName
            userIcon: sessionManager.userIcon
        }

        Column {
            id: form
            anchors.horizontalCenter: parent.horizontalCenter
            width: 340
            spacing: 10

            // The password pill: 48 px, radius 24, 10 % white fill, 1.5 px accent border and a
            // 4 px accent halo while focused.
            Item {
                id: pill
                width: parent.width
                height: 48

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: height / 2
                    antialiasing: true
                    color: "transparent"
                    border.width: 4
                    border.color: PfStyle.accentHalo
                    visible: passwordBox.activeFocus
                }
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    antialiasing: true
                    color: PfStyle.fieldFill
                }
                // The 1.5 px edge over the fill (CSS border over its background).
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    antialiasing: true
                    color: "transparent"
                    border.width: 1.5
                    border.color: passwordBox.activeFocus ? PfStyle.accent : PfStyle.fieldBorder
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 6
                    spacing: 8

                    PasswordField {
                        id: passwordBox
                        objectName: "passwordBox"

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        text: PasswordSync.password
                        placeholderText: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:placeholder in text field", "Password")
                        focus: true
                        // qmllint disable missing-property
                        enabled: !sessionManager.authenticatorObject || !sessionManager.authenticatorObject.graceLocked
                        // qmllint enable missing-property

                        // Cursor blinking only while shown: the hidden field keeps the focus
                        // so that the first key press wakes the prompt.
                        cursorVisible: visible

                        onAccepted: {
                            if (sessionManager.lockScreenUiVisible) {
                                sessionManager.startLogin();
                            }
                        }

                        Connections {
                            target: sessionManager.lockRoot
                            ignoreUnknownSignals: true
                            function onClearPassword() {
                                passwordBox.forceActiveFocus();
                                passwordBox.text = "";
                                passwordBox.text = Qt.binding(() => PasswordSync.password);
                            }
                            function onNotificationRepeated() {
                                sessionManager.playHighlightAnimation();
                            }
                        }
                    }
                    Binding {
                        target: PasswordSync
                        property: "password"
                        value: passwordBox.text
                    }

                    RoundButton {
                        id: revealButton
                        Layout.alignment: Qt.AlignVCenter
                        visible: KConfig.KAuthorized.authorize("lineedit_reveal_password")
                        iconPath: passwordBox.showPassword ? PfStyle.iconEye + PfStyle.iconSlash : PfStyle.iconEye
                        foreground: PfStyle.textMuted
                        text: passwordBox.showPassword
                              ? i18nd("plasma_shell_org.plasmafusion.lockshell", "Hide password")
                              : i18nd("plasma_shell_org.plasmafusion.lockshell", "Show password")
                        onClicked: {
                            passwordBox.showPassword = !passwordBox.showPassword;
                            passwordBox.forceActiveFocus();
                        }
                    }

                    RoundButton {
                        id: loginButton
                        objectName: "unlockButton"
                        Layout.alignment: Qt.AlignVCenter
                        fillColor: PfStyle.accentStrong
                        hoverFillColor: PfStyle.accentStrongHover
                        foreground: PfStyle.textOnAccent
                        iconPath: LayoutMirroring.enabled ? PfStyle.iconArrowLeft : PfStyle.iconArrowRight
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button accessible only", "Unlock")
                        onClicked: sessionManager.startLogin()
                    }
                }
            }

            // "Caps Lock is on" on the left, the fingerprint / smartcard hint on the right.
            Item {
                width: parent.width
                height: Math.max(capsRow.implicitHeight, hints.implicitHeight)
                visible: sessionManager.capsLockOn || sessionManager.fingerprintAvailable || sessionManager.smartcardAvailable

                Row {
                    id: capsRow
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.top: parent.top
                    spacing: 6
                    visible: sessionManager.capsLockOn

                    LineIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 14
                        path: PfStyle.iconCapsLock
                        color: PfStyle.warning
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Caps Lock is on")
                        color: PfStyle.warning
                        font.family: PfStyle.uiFont
                        font.pixelSize: 12
                        textFormat: Text.PlainText
                    }
                }

                Column {
                    id: hints
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.top: parent.top
                    width: sessionManager.capsLockOn ? parent.width - capsRow.implicitWidth - 32 : parent.width - 16
                    spacing: 2

                    FailableLabel {
                        authenticatorObject: sessionManager.authenticatorObject
                        available: sessionManager.fingerprintAvailable
                        kind: ScreenLocker.Authenticator.Fingerprint
                        label: i18nd("plasma_shell_org.plasmafusion.lockshell", "Use fingerprint")
                    }
                    FailableLabel {
                        authenticatorObject: sessionManager.authenticatorObject
                        available: sessionManager.smartcardAvailable
                        kind: ScreenLocker.Authenticator.Smartcard
                        label: i18nd("plasma_shell_org.plasmafusion.lockshell", "Use smartcard")
                    }
                }
            }

            // Prompts, information and errors from PAM (face and fingerprint guidance,
            // "Unlocking failed"), kept visible under the pill.
            Text {
                id: messageLabel
                width: parent.width
                visible: text.length > 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: PfStyle.text
                font.family: PfStyle.uiFont
                font.pixelSize: 13
                font.weight: Font.DemiBold
                textFormat: Text.PlainText
                transformOrigin: Item.Top

                Accessible.role: Accessible.AlertMessage
                Accessible.name: text

                SequentialAnimation {
                    id: bounceAnimation
                    loops: 1
                    PropertyAnimation {
                        target: messageLabel
                        properties: "scale"
                        from: 1.0
                        to: 1.1
                        duration: Kirigami.Units.longDuration
                        easing.type: Easing.OutQuad
                    }
                    PropertyAnimation {
                        target: messageLabel
                        properties: "scale"
                        from: 1.1
                        to: 1.0
                        duration: Kirigami.Units.longDuration
                        easing.type: Easing.InQuad
                    }
                }
            }
        }
    }

    // Login board power row: 44 px buttons with labels, 18 px apart, 28 px above the edge.
    Row {
        id: actionRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        spacing: 18
    }

    // A hint that is replaced by the authenticator's error for a moment when that kind of
    // authentication fails (the Plasma lock screen's FailableLabel).
    component FailableLabel: Text {
        id: failableLabel

        required property QtObject authenticatorObject
        required property bool available
        required property int kind
        required property string label

        property bool showingError: false
        // The authenticator's own instruction (pam_fprintd: "Place your finger on …"); shown
        // instead of the short hint once it has sent one, so its guidance stays visible.
        property string infoText: ""
        readonly property string restingText: infoText.length > 0 ? infoText : label

        anchors.right: parent.right
        width: parent.width
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.WordWrap
        visible: available
        text: restingText
        onAvailableChanged: {
            if (!available) {
                infoText = "";
            }
        }
        color: showingError ? PfStyle.warning : PfStyle.link
        font.family: PfStyle.uiFont
        font.pixelSize: 12
        font.weight: Font.DemiBold
        font.styleName: PfStyle.bold
        textFormat: Text.PlainText

        RejectPasswordAnimation {
            id: rejectAnimation
            target: failableLabel
            onFinished: restoreTimer.restart()
        }

        Connections {
            target: failableLabel.authenticatorObject
            ignoreUnknownSignals: true
            function onNoninteractiveError(kind, authenticator) {
                if (kind & failableLabel.kind) {
                    failableLabel.showingError = true;
                    failableLabel.text = Qt.binding(() => authenticator.errorMessage);
                    rejectAnimation.start();
                }
            }
            function onNoninteractiveInfo(kind, authenticator) {
                if ((kind & failableLabel.kind) && authenticator && authenticator.infoMessage) {
                    failableLabel.infoText = authenticator.infoMessage;
                }
            }
        }
        Timer {
            id: restoreTimer
            interval: Kirigami.Units.humanMoment
            onTriggered: {
                failableLabel.showingError = false;
                failableLabel.text = Qt.binding(() => failableLabel.restingText);
            }
        }
    }
}
