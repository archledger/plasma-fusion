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
import org.kde.plasma.workspace.dbus as DBus

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

    function handleMessage(msg, urgent) {
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
        announce(msg, urgent === true);
    }

    // Screen readers hear every PAM message (face and fingerprint guidance, errors) as it
    // arrives, also a repeated one, whether or not the prompt is shown (GAPS G25). Announced
    // from the full-screen item, which is always visible.
    function announce(msg, urgent) {
        lockScreenRoot.Accessible.announce(msg, urgent ? Accessible.Assertive : Accessible.Polite);
    }

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    // The user's accent for the focus border, halo, unlock button and focus rings (PfStyle.tint).
    // The lock screen is always dark, whatever the scheme's Complementary background.
    FusionAccent {
        id: accentTint
        dark: true
    }
    Binding {
        target: PfStyle
        property: "tint"
        value: accentTint
    }

    // Tablet posture from KWin (TABLET 4.13): touch-sized controls and the prompt higher up.
    FusionTablet {
        id: tabletState
    }

    // The on-screen keyboard (TABLET2 P0). On Wayland, Plasma 6.7.5's keyboard toggle on the lock screen
    // only moves the layout, and KWin shows its keyboard only when a text field asks for it after touch
    // or pen input. After locking with a key (Meta+L) the password field already has the focus, so a
    // finger tap brought no keyboard (private sessions lk10-old and lk10-new). Ask KWin directly. Its
    // forceActivate shows the keyboard whatever the last input was, so only touch and pen call it here
    // (the keyboard button aside), and in laptop posture Plasma Fusion runs no input method at all.
    function showKeyboard(): void {
        if (!Qt.platform.pluginName.includes("wayland") || !Keyboards.KWinVirtualKeyboard.available) {
            return;
        }
        DBus.SessionBus.asyncCall({
            "service": "org.kde.KWin",
            "path": "/VirtualKeyboard",
            "iface": "org.kde.kwin.VirtualKeyboard",
            "member": "forceActivate",
            "arguments": []
        });
    }
    function hideKeyboard(): void {
        if (Qt.platform.pluginName.includes("wayland")) {
            Keyboards.KWinVirtualKeyboard.active = false;
        } else if (inputPanel.keyboardActive) {
            inputPanel.showHide();
        }
    }
    function focusPasswordAndShowKeyboard(): void {
        mainBlock.mainPasswordBox.forceActiveFocus();
        showKeyboard();
    }
    Connections {
        target: mainBlock.mainPasswordBox
        function onTouched(): void {
            if (tabletState.tablet) {
                lockScreenUi.showKeyboard();
            }
        }
    }

    Motion {
        id: motion
    }

    // Text scale and pixel grid of the lock screen window (docs/parts/lockscreen.md, "Text
    // scale"): text, the pills and cards that hold it and the gaps next to it follow the user's
    // text size; the clock, the avatar, the round buttons and the screen margins do not.
    readonly property alias metrics: fusionMetrics
    FusionMetrics {
        id: fusionMetrics
        area: Qt.rect(0, 0, lockScreenUi.width, lockScreenUi.height)
        tablet: tabletState.tablet
    }
    // The Lock board's sizes in proportion to the screen (ADAPTIVE 5.10): 1 at 1440 x 900.
    readonly property real boardScale: Math.max(0.7, Math.min(1.4, Math.min(width / 1440, height / PfStyle.boardHeight)))

    // qmllint disable unqualified
    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) { // if this is coming from the noninteractive authenticators
                return;
            }
            const msg = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed");
            lockScreenUi.handleMessage(msg, true);
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
                        userListModel: users,
                        metrics: lockScreenUi.metrics
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
            lockScreenUi.handleMessage(authenticator.errorMessage, true);
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

    // The password field keeps the keyboard focus while the prompt is hidden, so the first key
    // goes straight into it and the root's key handler never sees it: typing shows the prompt
    // (without it, only a pointer resting over the screen did, through blockUI), and every key
    // keeps it up.
    Connections {
        target: mainBlock.mainPasswordBox
        function onTextEdited() {
            if (!lockScreenRoot.uiVisible) {
                lockScreenRoot.uiVisible = true;
            } else if (!lockScreenRoot.blockUI) {
                fadeoutTimer.restart();
            }
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

        // The whole screen: a click or a key shows the prompt. Screen readers hear its name, and
        // the PAM messages are announced from it (announce()).
        Accessible.role: Accessible.Pane
        Accessible.name: i18nd("plasma_shell_org.plasmafusion.lockshell", "Lock screen")
        Accessible.description: tabletState.tablet
            ? i18nd("plasma_shell_org.plasmafusion.lockshell", "Swipe up or press any key to unlock")
            : i18nd("plasma_shell_org.plasmafusion.lockshell", "Press any key or click to unlock")

        property bool uiVisible: false
        property bool seenPositionChange: false
        // Tablet posture (TABLET2 L1): how far the current swipe has lifted the idle screen, and when
        // the last finger or pen press began (a touch press only wakes the screen).
        property real swipeLift: 0
        property real touchPressAt: 0
        // The last pointer position (tablet posture: a move must travel to count, see onPositionChanged).
        property point lastPointer: Qt.point(-1, -1)
        // The swipe asked for the keyboard: requested once the prompt is in (a hidden field gets no
        // keyboard from KWin, l1a).
        property bool keyboardOnPrompt: false
        onPromptFactorChanged: {
            if (keyboardOnPrompt && promptFactor >= 0.3) {
                keyboardOnPrompt = false;
                Qt.callLater(lockScreenUi.focusPasswordAndShowKeyboard);
            }
        }
        // A finger does not hover, so in tablet posture typed text or the on-screen keyboard alone
        // keep the prompt up.
        property bool blockUI: (containsMouse || tabletState.tablet) && (mainStack.depth > 1 || mainBlock.mainPasswordBox.text.length > 0 || inputPanel.keyboardActive)

        // 0 = idle (Lock board), 1 = prompt shown (Login board); animated (BACKLOG S1): the
        // prompt comes in over 300 ms, decelerating, and goes in 200 ms; both follow Plasma's
        // animation speed, and reduced motion switches at once.
        property real promptFactor: uiVisible ? 1 : 0
        Behavior on promptFactor {
            id: promptBehavior
            enabled: motion.animate
            NumberAnimation {
                duration: promptBehavior.targetValue > 0.5 ? motion.scaled(motion.surface, 1.2) : motion.popupIn
                easing.type: promptBehavior.targetValue > 0.5 ? Easing.Bezier : motion.exitEasing
                easing.bezierCurve: motion.decelerate
            }
        }

        x: parent.x
        y: parent.y
        width: parent.width
        height: parent.height
        hoverEnabled: true
        cursorShape: uiVisible ? Qt.ArrowCursor : Qt.BlankCursor
        drag.filterChildren: true
        onPressed: {
            // Tablet posture (TABLET2 L1, phone-style): a finger or pen press on the idle screen
            // only nudges the "Swipe up to unlock" hint, so taps in a bag do not raise the prompt
            // and the keyboard; the swipe below shows them. A mouse press shows the prompt as before.
            if (tabletState.tablet && !uiVisible && Date.now() - touchPressAt < 500) {
                hintNudge.restart();
                return;
            }
            uiVisible = true;
        }
        // Handlers see a press before their item, so the press time is known in onPressed; taps on
        // controls (media, notification cards) stay with the controls.
        PointHandler {
            id: touchPoint
            acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Stylus
            // press and release: Qt synthesises mouse moves around a touch (see onPositionChanged)
            onActiveChanged: lockScreenRoot.touchPressAt = Date.now()
        }
        // Swipe up (96 px or 800 px/s) in tablet posture: the prompt with the on-screen keyboard.
        DragHandler {
            id: unlockSwipe
            enabled: tabletState.tablet && !lockScreenRoot.uiVisible
            acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Stylus
            target: null
            xAxis.enabled: false
            dragThreshold: 12
            onTranslationChanged: {
                if (active) {
                    lockScreenRoot.swipeLift = Math.max(0, -translation.y);
                }
            }
            onActiveChanged: {
                if (active) {
                    return;
                }
                const dy = centroid.position.y - centroid.pressPosition.y;
                if (-dy >= 96 || centroid.velocity.y <= -800) {
                    lockScreenRoot.keyboardOnPrompt = true;
                    lockScreenRoot.uiVisible = true;
                } else {
                    hintNudge.restart();
                }
                liftBack.restart();
            }
        }
        NumberAnimation {
            id: liftBack
            target: lockScreenRoot
            property: "swipeLift"
            to: 0
            duration: motion.popupOut
            easing.type: motion.exitEasing
        }
        onPositionChanged: mouse => {
            // In tablet posture the mouse moves Qt synthesises around a touch are not the pointer
            // moving, and neither is a pointer event that does not travel: KWin sends one at the
            // screen centre when an input device is added (l1d: every test client did it, and the
            // prompt came up before the swipe). A mouse in tablet posture still shows the prompt.
            if (tabletState.tablet) {
                const last = lastPointer;
                lastPointer = Qt.point(mouse.x, mouse.y);
                if (touchPoint.active || Date.now() - touchPressAt < 600
                        || last.x < 0 || Math.abs(mouse.x - last.x) + Math.abs(mouse.y - last.y) <= 8) {
                    return;
                }
            }
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
            // A finger lifting off counts as leaving the area: in tablet posture only the timeout hides
            // the prompt, or a tap would show it for the length of the touch.
            if (!tabletState.tablet) {
                uiVisible = false;
            }
        }
        Keys.onEscapePressed: {
            // If the escape key is pressed, kscreenlocker will turn off the screen.
            // We do not want to show the password prompt in this case.
            if (uiVisible) {
                uiVisible = false;
                lockScreenUi.hideKeyboard();
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

        NumberAnimation {
            id: launchAnimation
            target: lockScreenRoot
            property: "opacity"
            from: 0
            to: 1
            duration: motion.scaled(motion.surface, 1.2)
            easing.type: Easing.Bezier
            easing.bezierCurve: motion.decelerate
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

        // Idle: date and large clock (Lock board, 92 px from the top of a 900 px screen; the
        // clock 148 px there, in proportion to the screen elsewhere).
        BigClock {
            id: bigClock
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(lockScreenRoot.height * 92 / PfStyle.boardHeight) - 12 * lockScreenRoot.promptFactor
               - 0.3 * lockScreenRoot.swipeLift
            metrics: lockScreenUi.metrics
            sizeScale: lockScreenUi.boardScale
            dateTime: timeSource.dateTime
            opacity: lockScreenUi.alwaysShowClock && !lockScreenUi.hideClockWhenIdle ? 1 - lockScreenRoot.promptFactor : 0
            visible: opacity > 0
        }

        // Idle: "Press any key or click to unlock" (Lock board, 430 px from the top). Tablet posture
        // (TABLET2 L1): "Swipe up to unlock" near the bottom over a home-pill handle, as on a phone;
        // it follows the swipe and fades, and a tap nudges it.
        UnlockHint {
            id: unlockHint
            objectName: "unlockHint"
            anchors.horizontalCenter: parent.horizontalCenter
            y: tabletState.tablet
               ? lockScreenRoot.height - height - 44 - 0.5 * lockScreenRoot.swipeLift
               : Math.round(lockScreenRoot.height * 430 / PfStyle.boardHeight)
            backdrop: backdrop
            metrics: lockScreenUi.metrics
            text: tabletState.tablet
                  ? i18nd("plasma_shell_org.plasmafusion.lockshell", "Swipe up to unlock")
                  : i18nd("plasma_shell_org.plasmafusion.lockshell", "Press any key or click to unlock")
            opacity: (1 - lockScreenRoot.promptFactor) * (1 - Math.min(1, lockScreenRoot.swipeLift / 160))
            visible: opacity > 0
        }
        SequentialAnimation {
            id: hintNudge
            NumberAnimation {
                target: unlockHint
                property: "scale"
                to: 1.06
                duration: motion.press
                easing.type: motion.standardEasing
            }
            NumberAnimation {
                target: unlockHint
                property: "scale"
                to: 1
                duration: motion.toggle
                easing.type: motion.standardEasing
            }
        }
        Rectangle {
            // the home-pill handle under the hint (tablet posture, idle)
            objectName: "unlockHandle"
            visible: tabletState.tablet && opacity > 0
            opacity: unlockHint.opacity
            anchors.horizontalCenter: parent.horizontalCenter
            y: lockScreenRoot.height - 14 - 0.5 * lockScreenRoot.swipeLift
            width: 120
            height: 5
            radius: 2.5
            color: Qt.rgba(1, 1, 1, 0.85)
        }

        // Prompt: small clock top left (Login board).
        SmallClock {
            x: LayoutMirroring.enabled ? lockScreenRoot.width - width - 32 : 32
            y: 28
            metrics: lockScreenUi.metrics
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
            objectName: "mainStack"
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
                metrics: lockScreenUi.metrics
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
                onAnnouncement: (text, urgent) => lockScreenUi.announce(text, urgent)

                onPasswordResult: password => {
                    // qmllint disable unqualified
                    authenticator.respond(password)
                    // qmllint enable unqualified
                }

                actionItems: [
                    PowerButton {
                        metrics: lockScreenUi.metrics
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "Slee&p")
                        iconPath: PfStyle.iconSleep
                        onClicked: sessionManagement.suspend()
                        visible: sessionManagement.canSuspend
                    },
                    PowerButton {
                        metrics: lockScreenUi.metrics
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "&Hibernate")
                        iconPath: PfStyle.iconHibernate
                        onClicked: sessionManagement.hibernate()
                        visible: sessionManagement.canHibernate
                    },
                    PowerButton {
                        metrics: lockScreenUi.metrics
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
            readonly property bool sharesBottomRow: lockScreenRoot.width < width + 2 * (PfStyle.edge + lockScreenUi.metrics.px(348) + 16)
            readonly property real limit: sharesBottomRow
                ? lockScreenRoot.height - PfStyle.edge - lockScreenUi.metrics.px(72) - 16
                : lockScreenRoot.height - (lockScreenRoot.uiVisible ? mainBlock.height - mainBlock.actionsTop + 16 : PfStyle.edge)

            anchors.horizontalCenter: parent.horizontalCenter
            y: lockScreenRoot.uiVisible ? Math.max(baseY, promptY) : baseY
            width: Math.min(lockScreenUi.metrics.px(400), lockScreenRoot.width - 64)
            metrics: lockScreenUi.metrics
            backdrop: backdrop
            visible: lockScreenUi.showNotifications && groups.length > 0 && maximumCards > 0
            // The singleton (and with it the watcher registration with Plasma's notification
            // server) is only created when the cards are enabled.
            groups: lockScreenUi.showNotifications ? LockNotifications.groups : []
            showSummaries: lockScreenUi.showNotificationSummaries
            maximumCards: Math.max(0, Math.floor((limit - y + spacing) / (cardHeight + spacing)))

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
        Binding {
            target: mediaLoader.item
            property: "metrics"
            value: lockScreenUi.metrics
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
            metrics: lockScreenUi.metrics
            virtualKeyboardAvailable: inputPanel.status === Loader.Ready
                                      && (!Qt.platform.pluginName.includes("wayland") || Keyboards.KWinVirtualKeyboard.available)
            virtualKeyboardActive: inputPanel.keyboardActive
            onVirtualKeyboardToggled: {
                // Otherwise the password field loses focus and virtual keyboard
                // keystrokes get eaten
                mainBlock.mainPasswordBox.forceActiveFocus();
                if (!Qt.platform.pluginName.includes("wayland")) {
                    inputPanel.showHide();
                } else if (inputPanel.keyboardActive) {
                    // KWin owns the keyboard on Wayland (see showKeyboard()).
                    lockScreenUi.hideKeyboard();
                } else {
                    lockScreenUi.showKeyboard();
                }
            }
            onInteracted: fadeoutTimer.running = false
        }

        VirtualKeyboardLoader {
            id: inputPanel
            objectName: "inputPanel"

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
