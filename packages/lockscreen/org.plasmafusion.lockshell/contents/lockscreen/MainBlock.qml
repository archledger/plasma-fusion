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
    // Text scale and pixel grid of the lock screen window (LockScreenUi).
    required property FusionMetrics metrics
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

    // Tablet posture (FusionMetrics.tablet follows KWin): touch-sized controls (TABLET 4.13).
    readonly property bool tablet: metrics.tablet
    // The y position that has to stay visible above the on-screen keyboard: the whole prompt,
    // messages included, 24 px above it (TABLET 4.13).
    property int visibleBoundary: Math.ceil(card.y + card.height + 24)
    // Bottom of the prompt (avatar to message area) and top of the power buttons.
    readonly property real contentBottom: card.y + card.height
    readonly property real actionsTop: actionRow.visibleChildren.length > 0 ? actionRow.y : height

    signal passwordResult(string password)
    signal userSelected()
    // A message for screen readers (LockScreenUi announces it).
    signal announcement(string text, bool urgent)

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
        objectName: "promptCard"
        anchors.horizontalCenter: parent.horizontalCenter
        // Login board: 210 px from the top of a 900 px screen. Tablet: the avatar, name and
        // password pill centred at 38 % of the height (a third in portrait); messages hang below
        // without moving them.
        y: sessionManager.tablet
           ? Math.max(Kirigami.Units.gridUnit, Math.round(sessionManager.height * (sessionManager.metrics.portrait ? 1 / 3 : 0.38)
                                                          - (header.height + spacing + pill.height) / 2))
           : Math.max(Kirigami.Units.gridUnit, Math.round(sessionManager.height * 210 / PfStyle.boardHeight))
        // min(400 x text scale, W - 64); in tablet posture at least 400 (TABLET 4.13).
        width: Math.min(sessionManager.tablet ? Math.max(400, sessionManager.metrics.px(400)) : sessionManager.metrics.px(400),
                        sessionManager.width - 64)
        spacing: sessionManager.metrics.px(22)

        UserHeader {
            id: header
            anchors.horizontalCenter: parent.horizontalCenter
            metrics: sessionManager.metrics
            userName: sessionManager.userName
            userIcon: sessionManager.userIcon
        }

        Column {
            id: form
            anchors.horizontalCenter: parent.horizontalCenter
            width: sessionManager.tablet ? card.width : Math.min(sessionManager.metrics.px(340), card.width)
            spacing: sessionManager.metrics.px(10)

            // The password pill: 48 px, radius 24, 10 % white fill, 1.5 px accent border and a
            // 4 px accent halo while focused. Tablet: at least 48 px, as wide as the prompt.
            Item {
                id: pill
                objectName: "passwordPill"
                width: parent.width
                height: sessionManager.tablet ? Math.max(48, sessionManager.metrics.px(48)) : sessionManager.metrics.px(48)
                // Reveal and unlock buttons: 36 px, touch-sized (44) in tablet posture.
                readonly property real buttonSize: sessionManager.tablet ? Math.min(44, height - 4) : 36

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
                    anchors.leftMargin: sessionManager.metrics.px(18)
                    anchors.rightMargin: sessionManager.tablet ? (pill.height - pill.buttonSize) / 2 : sessionManager.metrics.px(6)
                    spacing: sessionManager.metrics.px(8)

                    PasswordField {
                        id: passwordBox
                        objectName: "passwordBox"
                        metrics: sessionManager.metrics

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
                        objectName: "revealButton"
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: pill.buttonSize
                        implicitHeight: pill.buttonSize
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
                        implicitWidth: pill.buttonSize
                        implicitHeight: pill.buttonSize
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
                    anchors.leftMargin: sessionManager.metrics.px(8)
                    anchors.top: parent.top
                    spacing: sessionManager.metrics.px(6)
                    visible: sessionManager.capsLockOn

                    LineIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: sessionManager.metrics.px(14)
                        path: PfStyle.iconCapsLock
                        color: PfStyle.warning
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Caps Lock is on")
                        color: PfStyle.warning
                        font.family: PfStyle.uiFont
                        font.pixelSize: sessionManager.metrics.font(12)
                        textFormat: Text.PlainText
                    }
                }

                Column {
                    id: hints
                    anchors.right: parent.right
                    anchors.rightMargin: sessionManager.metrics.px(8)
                    anchors.top: parent.top
                    width: sessionManager.capsLockOn ? parent.width - capsRow.implicitWidth - sessionManager.metrics.px(32)
                                                     : parent.width - sessionManager.metrics.px(16)
                    spacing: sessionManager.metrics.px(2)

                    FailableLabel {
                        metrics: sessionManager.metrics
                        authenticatorObject: sessionManager.authenticatorObject
                        available: sessionManager.fingerprintAvailable
                        kind: ScreenLocker.Authenticator.Fingerprint
                        label: i18nd("plasma_shell_org.plasmafusion.lockshell", "Use fingerprint")
                        onAnnounce: (text, urgent) => sessionManager.announcement(text, urgent)
                    }
                    FailableLabel {
                        metrics: sessionManager.metrics
                        authenticatorObject: sessionManager.authenticatorObject
                        available: sessionManager.smartcardAvailable
                        kind: ScreenLocker.Authenticator.Smartcard
                        label: i18nd("plasma_shell_org.plasmafusion.lockshell", "Use smartcard")
                        onAnnounce: (text, urgent) => sessionManager.announcement(text, urgent)
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
                font.pixelSize: sessionManager.metrics.font(13)
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
        objectName: "actionRow"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        spacing: sessionManager.metrics.px(18)
    }

    // A hint that is replaced by the authenticator's error for a moment when that kind of
    // authentication fails (the Plasma lock screen's FailableLabel).
    component FailableLabel: Text {
        id: failableLabel

        required property FusionMetrics metrics
        required property QtObject authenticatorObject
        required property bool available
        required property int kind
        required property string label

        // Guidance and errors for screen readers (MainBlock.announcement).
        signal announce(string text, bool urgent)

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
        font.pixelSize: metrics.font(12)
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
                    failableLabel.announce(authenticator.errorMessage, true);
                }
            }
            function onNoninteractiveInfo(kind, authenticator) {
                if ((kind & failableLabel.kind) && authenticator && authenticator.infoMessage) {
                    failableLabel.infoText = authenticator.infoMessage;
                    failableLabel.announce(authenticator.infoMessage, false);
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
