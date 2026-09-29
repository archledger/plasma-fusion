/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQml
import QtQuick
import QtQuick.Controls

import org.kde.kirigami as Kirigami
import org.kde.plasma.clock as PlasmaClock
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.plasma.workspace.keyboardlayout as Keyboards

import org.kde.plasma.private.sessions
import org.kde.breeze.components

// Plasma Fusion lock screen (Lock and Login boards). The behaviour is the Plasma 6.7 lock
// screen's: the same authenticator handlers, timers, wake-up rules, virtual keyboard, keyboard
// layout, session actions, media controls and OSD. Only the presentation differs:
//   idle   (Lock board): dimmed wallpaper, date and 148 px clock, "Press any key or click to
//          unlock" pill, notification cards, media card, status chip;
//   prompt (Login board): blurred wallpaper, small clock top left, avatar, name and the
//          password pill with its hints and PAM messages, power buttons along the bottom.
Item {
    id: lockScreenUi

    // LockScreen.qml's root: notification text, clearPassword(), notificationRepeated(),
    // viewVisible.
    property var lockRoot: null

    // If we're using software rendering, draw no shadows and blur
    // See https://bugs.kde.org/show_bug.cgi?id=398317
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software

    // Lock screen settings (kscreenlockerrc [Greeter][LnF][General], see config.xml).
    function setting(key, fallback) {
        // qmllint disable unqualified
        if (typeof config === "undefined" || !config) {
            return fallback;
        }
        const value = config[key];
        // qmllint enable unqualified
        return value === undefined || value === null ? fallback : value;
    }
    readonly property bool alwaysShowClock: setting("alwaysShowClock", true)
    readonly property bool hideClockWhenIdle: setting("hideClockWhenIdle", false)
    readonly property bool showMediaControls: setting("showMediaControls", true)
    readonly property bool showNotifications: setting("showNotifications", true)
    readonly property bool showNotificationSummaries: setting("showNotificationSummaries", false)

    function handleMessage(msg) {
        if (!msg) {
            return;
        }
        if (!lockRoot.notification) {
            lockRoot.notification += msg;
        } else if (lockRoot.notification.includes(msg)) {
            lockRoot.notificationRepeated();
        } else {
            lockRoot.notification += "\n" + msg;
        }
    }

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    // qmllint disable unqualified
    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) { // if this is coming from the noninteractive authenticators
                return;
            }
            const msg = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed");
            lockScreenUi.handleMessage(msg);
            graceLockTimer.restart();
            notificationRemoveTimer.restart();
            rejectPasswordAnimation.start();
        }

        function onSucceeded() {
            if (authenticator.hadPrompt) {
                Qt.quit();
            } else {
                mainStack.replace(null, Qt.resolvedUrl("NoPasswordUnlock.qml"),
                    {
                        userListModel: users
                    },
                    StackView.Immediate,
                );
                mainStack.forceActiveFocus();
            }
        }

        function onInfoMessageChanged() {
            lockScreenUi.handleMessage(authenticator.infoMessage);
        }

        function onErrorMessageChanged() {
            lockScreenUi.handleMessage(authenticator.errorMessage);
        }

        function onPromptChanged(msg) {
            lockScreenUi.handleMessage(authenticator.prompt);
        }
        function onPromptForSecretChanged(msg) {
            mainBlock.showPassword = false;
            mainBlock.mainPasswordBox.forceActiveFocus();
        }
    }
    // qmllint enable unqualified

    SessionManagement {
        id: sessionManagement
    }

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    Connections {
        target: sessionManagement
        function onAboutToSuspend() {
            lockScreenUi.lockRoot.clearPassword();
        }
    }

    RejectPasswordAnimation {
        id: rejectPasswordAnimation
        target: mainBlock
    }

    PlasmaClock.Clock {
        id: timeSource
        trackSeconds: false
    }

    MouseArea {
        id: lockScreenRoot
        objectName: "lockScreenRoot"

        property bool uiVisible: false
        property bool seenPositionChange: false
        property bool blockUI: containsMouse && (mainStack.depth > 1 || mainBlock.mainPasswordBox.text.length > 0 || inputPanel.keyboardActive)

        // 0 = idle (Lock board), 1 = prompt shown (Login board); animated.
        property real promptFactor: uiVisible ? 1 : 0
        Behavior on promptFactor {
            NumberAnimation {
                duration: Kirigami.Units.veryLongDuration * 2
                easing.type: Easing.InOutQuad
            }
        }

        x: parent.x
        y: parent.y
        width: parent.width
        height: parent.height
        hoverEnabled: true
        cursorShape: uiVisible ? Qt.ArrowCursor : Qt.BlankCursor
        drag.filterChildren: true
        onPressed: uiVisible = true;
        onPositionChanged: {
            uiVisible = seenPositionChange;
            seenPositionChange = true;
        }
        onUiVisibleChanged: {
            if (uiVisible) {
                Window.window.requestActivate();
            }

            if (blockUI) {
                fadeoutTimer.running = false;
            } else if (uiVisible) {
                fadeoutTimer.restart();
            }
            // qmllint disable unqualified
            authenticator.startAuthenticating();
            // qmllint enable unqualified
        }
        onBlockUIChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
                uiVisible = true;
            } else {
                fadeoutTimer.restart();
            }
        }
        onExited: {
            uiVisible = false;
        }
        Keys.onEscapePressed: {
            // If the escape key is pressed, kscreenlocker will turn off the screen.
            // We do not want to show the password prompt in this case.
            if (uiVisible) {
                uiVisible = false;
                if (inputPanel.keyboardActive) {
                    inputPanel.showHide();
                }
                lockScreenUi.lockRoot.clearPassword();
            }
        }
        Keys.onPressed: event => {
            uiVisible = true;
            event.accepted = false;
        }
        Timer {
            id: fadeoutTimer
            interval: 10000
            onTriggered: {
                if (!lockScreenRoot.blockUI) {
                    mainBlock.mainPasswordBox.showPassword = false;
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Timer {
            id: notificationRemoveTimer
            interval: 3000
            onTriggered: lockScreenUi.lockRoot.notification = ""
        }
        Timer {
            id: graceLockTimer
            interval: 3000
            onTriggered: {
                lockScreenUi.lockRoot.clearPassword();
                // qmllint disable unqualified
                authenticator.startAuthenticating();
                // qmllint enable unqualified
            }
        }

        PropertyAnimation {
            id: launchAnimation
            target: lockScreenRoot
            property: "opacity"
            from: 0
            to: 1
            duration: Kirigami.Units.veryLongDuration * 2
        }

        Component.onCompleted: launchAnimation.start();

        Backdrop {
            id: backdrop
            objectName: "backdrop"
            anchors.fill: parent
            // qmllint disable unqualified
            source: typeof wallpaper !== "undefined" && wallpaper ? wallpaper : null
            // qmllint enable unqualified
            factor: lockScreenRoot.promptFactor
        }

        // Idle: date and large clock (Lock board, 92 px from the top of a 900 px screen).
        BigClock {
            id: bigClock
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(lockScreenRoot.height * 92 / PfStyle.boardHeight) - 12 * lockScreenRoot.promptFactor
            dateTime: timeSource.dateTime
            opacity: lockScreenUi.alwaysShowClock && !lockScreenUi.hideClockWhenIdle ? 1 - lockScreenRoot.promptFactor : 0
            visible: opacity > 0
        }

        // Idle: "Press any key or click to unlock" (Lock board, 430 px from the top).
        UnlockHint {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(lockScreenRoot.height * 430 / PfStyle.boardHeight)
            backdrop: backdrop
            text: i18nd("plasma_shell_org.plasmafusion.lockshell", "Press any key or click to unlock")
            opacity: 1 - lockScreenRoot.promptFactor
            visible: opacity > 0
        }

        // Prompt: small clock top left (Login board).
        SmallClock {
            x: LayoutMirroring.enabled ? lockScreenRoot.width - width - 32 : 32
            y: 28
            dateTime: timeSource.dateTime
            opacity: lockScreenUi.alwaysShowClock ? lockScreenRoot.promptFactor : 0
            visible: opacity > 0
        }

        ListModel {
            id: users

            Component.onCompleted: {
                // qmllint disable unqualified
                users.append({
                    name: kscreenlocker_userName,
                    realName: kscreenlocker_userName,
                    icon: kscreenlocker_userImage !== ""
                          ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/")
                          : "",
                })
                // qmllint enable unqualified
            }
        }

        StackView {
            id: mainStack
            anchors {
                left: parent.left
                right: parent.right
            }
            height: lockScreenRoot.height
            focus: true //StackView is an implicit focus scope, so we need to give this focus so the item inside will have it

            // this isn't implicit, otherwise items still get processed for the scenegraph
            visible: opacity > 0
            opacity: lockScreenRoot.promptFactor

            initialItem: MainBlock {
                id: mainBlock
                objectName: "mainBlock"
                lockRoot: lockScreenUi.lockRoot
                // qmllint disable unqualified
                authenticatorObject: authenticator
                userName: kscreenlocker_userName
                // qmllint enable unqualified
                userIcon: users.count > 0 ? users.get(0).icon : ""
                lockScreenUiVisible: lockScreenRoot.uiVisible
                capsLockOn: capsLockState.locked

                enabled: !graceLockTimer.running

                StackView.onStatusChanged: {
                    // prepare for presenting again to the user
                    if (StackView.status === StackView.Activating) {
                        mainPasswordBox.clear();
                        mainPasswordBox.focus = true;
                        lockScreenUi.lockRoot.notification = "";
                    }
                }
                userListModel: users

                notificationMessage: lockScreenUi.lockRoot ? lockScreenUi.lockRoot.notification : ""

                onPasswordResult: password => {
                    // qmllint disable unqualified
                    authenticator.respond(password)
                    // qmllint enable unqualified
                }

                actionItems: [
                    PowerButton {
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "Slee&p")
                        iconPath: PfStyle.iconSleep
                        onClicked: sessionManagement.suspend()
                        visible: sessionManagement.canSuspend
                    },
                    PowerButton {
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "&Hibernate")
                        iconPath: PfStyle.iconHibernate
                        onClicked: sessionManagement.hibernate()
                        visible: sessionManagement.canHibernate
                    },
                    PowerButton {
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "Switch &User")
                        iconPath: PfStyle.iconSwitchUser
                        onClicked: {
                            sessionManagement.switchUser();
                        }
                        visible: sessionManagement.canSwitchUser
                    }
                ]
            }
        }

        // Notifications that arrived while locked (Lock board, 620 px from the top; below the
        // prompt while it is shown).
        NotificationCards {
            id: notificationCards
            objectName: "notificationCards"

            readonly property real baseY: Math.round(lockScreenRoot.height * 620 / PfStyle.boardHeight)
            readonly property real promptY: mainStack.y + mainBlock.contentBottom + 28
            // Room above the media card / status chip (or the power buttons while prompting).
            readonly property bool sharesBottomRow: lockScreenRoot.width < width + 2 * (PfStyle.edge + 348 + 16)
            readonly property real limit: sharesBottomRow
                ? lockScreenRoot.height - PfStyle.edge - 72 - 16
                : lockScreenRoot.height - (lockScreenRoot.uiVisible ? mainBlock.height - mainBlock.actionsTop + 16 : PfStyle.edge)

            anchors.horizontalCenter: parent.horizontalCenter
            y: lockScreenRoot.uiVisible ? Math.max(baseY, promptY) : baseY
            backdrop: backdrop
            visible: lockScreenUi.showNotifications && groups.length > 0 && maximumCards > 0
            // The singleton (and with it the watcher registration with Plasma's notification
            // server) is only created when the cards are enabled.
            groups: lockScreenUi.showNotifications ? LockNotifications.groups : []
            showSummaries: lockScreenUi.showNotificationSummaries
            maximumCards: Math.max(0, Math.floor((limit - y + 8) / 64))

            Behavior on y {
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.InOutQuad
                }
            }
        }

        // Media card, bottom left (Lock board).
        Loader {
            id: mediaLoader
            anchors {
                left: parent.left
                bottom: parent.bottom
                margins: PfStyle.edge
            }
            active: lockScreenUi.showMediaControls
            source: "MediaControls.qml"
        }
        Binding {
            target: mediaLoader.item
            property: "backdrop"
            value: backdrop
            when: mediaLoader.status === Loader.Ready
        }
        Connections {
            target: mediaLoader.item
            ignoreUnknownSignals: true
            function onInteracted() {
                fadeoutTimer.running = false;
            }
        }

        // Keyboard layout, virtual keyboard, network and battery, bottom right (Lock board).
        StatusChip {
            id: statusChip
            anchors {
                right: parent.right
                bottom: parent.bottom
                margins: PfStyle.edge
            }
            backdrop: backdrop
            virtualKeyboardAvailable: inputPanel.status === Loader.Ready
                                      && (!Qt.platform.pluginName.includes("wayland") || Keyboards.KWinVirtualKeyboard.available)
            virtualKeyboardActive: inputPanel.keyboardActive
            onVirtualKeyboardToggled: {
                // Otherwise the password field loses focus and virtual keyboard
                // keystrokes get eaten
                mainBlock.mainPasswordBox.forceActiveFocus();
                inputPanel.showHide();
            }
            onInteracted: fadeoutTimer.running = false
        }

        VirtualKeyboardLoader {
            id: inputPanel

            z: 1

            screenRoot: lockScreenRoot
            mainStack: mainStack
            mainBlock: mainBlock
            passwordField: mainBlock.mainPasswordBox
        }

        Loader {
            z: 2
            active: !!lockScreenUi.lockRoot && lockScreenUi.lockRoot.viewVisible === true
            source: "LockOsd.qml"
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Kirigami.Units.gridUnit
            }
        }
    }
}
