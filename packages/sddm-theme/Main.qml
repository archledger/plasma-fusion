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
import QtCore

Rectangle {
    id: root
    color: "#0f1428"

    // The user the card shows (filled by UserSwitcher's delegates)
    property string personName: ""
    property url personIcon: ""
    property string personLetter: ""
    property string loginName: ""
    // SDDM's login call is asynchronous; keep one request and its displayed identity stable.
    property bool authenticating: false
    // primaryScreen is a creation-time snapshot; screenModel.primary reads the current primary.
    // SDDM 0.21 never emits primaryChanged, so poll the getter at a login-screen pace.
    property bool primaryNow: primaryScreen === true
    property bool primaryInitialized: false
    readonly property bool interactive: primaryNow
    readonly property real footerTop: Math.min(session.y, powerButtons.y)
    // Qt's virtual keyboard (VirtualKeyboard.qml), created here rather than by a Loader's URL: on a
    // Wayland greeter (the compositor's keyboard) or without QtQuick.VirtualKeyboard there is no
    // panel and no button, and no warning at every greeter start.
    readonly property Component keyboardComponent: Qt.platform.pluginName.indexOf("wayland") < 0
        ? Qt.createComponent("VirtualKeyboard.qml") : null
    readonly property bool keyboardShown: inputPanel.item !== null && inputPanel.item.active
    // SDDM builds one QML engine per screen, so a QML property cannot lock a login across
    // displays. A QSettings-backed file can; any live screen renews a heartbeat while PAM runs.
    readonly property string viewToken: Math.random().toString(36).substring(2)
    // SDDM launches a greeter with a random --socket name (sddm-<display>-<random>), so this key
    // scopes the lock to one greeter process; another seat's greeter gets its own category.
    property string greeterKey: {
        const args = Qt.application.arguments;
        const at = args.indexOf("--socket");
        const socket = at >= 0 && at + 1 < args.length ? String(args[at + 1]) : "";
        const base = socket.replace(/\\/g, "/").split("/").pop();
        return base.replace(/[^A-Za-z0-9_.-]/g, "_");
    }
    readonly property string authLockPath: StandardPaths.writableLocation(
        StandardPaths.GenericConfigLocation) + "/plasmafusion-auth.ini"
    property bool lockOwned: false

    Settings {
        id: authState
        location: root.authLockPath
        category: "Auth-" + (root.greeterKey !== "" ? root.greeterKey : "default")
    }

    function readAuthLock() {
        authState.sync();
        return {
            pending: authState.value("pending", false) === true,
            owner: String(authState.value("owner", "")),
            heartbeat: Number(authState.value("heartbeat", 0))
        };
    }

    function writeAuthLock(pending, owner, heartbeat) {
        authState.setValue("pending", pending);
        authState.setValue("owner", owner);
        authState.setValue("heartbeat", heartbeat);
        authState.sync();
        return authState.value("pending", false) === pending
            && String(authState.value("owner", "")) === owner;
    }

    function acquireAuthLock() {
        const lock = readAuthLock();
        if (lock.pending && Date.now() - lock.heartbeat < 5000) {
            return false;
        }
        writeAuthLock(true, viewToken, Date.now());
        lockOwned = true;
        return true;
    }

    function clearAuthLock() {
        writeAuthLock(false, "", 0);
    }

    function refreshAuthLock() {
        const lock = readAuthLock();
        if (lock.pending && Date.now() - lock.heartbeat < 5000) {
            if (!root.authenticating) {
                root.authenticating = true;
                root.lockOwned = false;
                card.message = qsTr("Signing in on another display…");
            }
            // A surviving screen renews the shared request even if the submitting screen's view
            // was removed; only an entirely gone greeter stops the heartbeat.
            authState.setValue("heartbeat", Date.now());
            authState.sync();
            return;
        }
        if (lock.pending) {
            // The owning view or greeter is gone; reclaim rather than stay locked forever.
            clearAuthLock();
        }
        if (root.authenticating && !root.lockOwned) {
            root.authenticating = false;
            card.message = "";
        }
    }

    function refreshPrimary() {
        let now = primaryScreen === true;
        if (typeof screenModel !== "undefined" && screenModel && screenModel.primary !== undefined) {
            now = screenModel.primary === 0;
        }
        if (!primaryInitialized) {
            primaryNow = now;
            primaryInitialized = true;
            return;
        }
        if (now === primaryNow) {
            return;
        }
        primaryNow = now;
        if (now) {
            initUsers();
        } else {
            // Do not leave a revealed credential or typed name on a now-secondary display.
            card.clearPassword();
            card.clearUsername();
        }
    }

    function initUsers() {
        // An empty model has no delegate to report the initial choice; select Other through the
        // same state path as a click so the prompt, ring and Accessible.selected agree. A
        // non-empty model is initialized by its delegates, which do not depend on input gating.
        if (!users.sent && userModel.count === 0) {
            users.selectOtherInitial();
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.refreshPrimary();
            root.refreshAuthLock();
        }
    }

    function login(user, password) {
        if (authenticating || !interactive) {
            return;
        }
        const who = user !== "" ? user : loginName;
        if (who === "") {
            card.message = qsTr("Enter a username");
            card.clearPassword();
            card.focusUsername();
            return;
        }
        if (!session.valid) {
            card.message = qsTr("No sessions available");
            card.clearPassword();
            return;
        }
        if (!acquireAuthLock()) {
            card.message = qsTr("Login already in progress");
            card.clearPassword();
            return;
        }
        authenticating = true;
        lockOwned = true;
        card.message = qsTr("Signing in…");
        // Do not leave a revealed credential on screen while PAM is pending.
        card.clearPassword();
        sddm.login(who, card.passwordRequired ? password : "", session.index);
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            authenticating = false;
            lockOwned = false;
            clearAuthLock();
            card.message = qsTr("Login failed");
            card.clearPassword();
            // clearPassword focuses the name field for Other user; only the password was wrong.
            card.focusPasswordField();
        }
        function onLoginSucceeded() {
            authenticating = false;
            lockOwned = false;
            clearAuthLock();
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

    // ---- Top right: the keyboard layout pill and the accessibility button (the board's third,
    // the Wi-Fi and battery pill, has no SDDM API) ----
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 28
        anchors.rightMargin: 28
        spacing: 8

        Rectangle {
            id: keyboardPill
            visible: keyboard.layouts.length > 1
            width: Math.max(58, keyboardLabel.implicitWidth + 24)
            height: 34
            radius: 17
            color: "#14ffffff"
            Accessible.name: qsTr("Keyboard layout")
            Accessible.description: keyboardLabel.text
            Accessible.role: Accessible.Button
            activeFocusOnTab: true
            enabled: root.interactive && !root.authenticating
            border.color: activeFocus ? "#6aa9ff" : "transparent"
            border.width: activeFocus ? 2 : 0
            function advance() {
                if (!root.interactive || root.authenticating) {
                    return;
                }
                if (keyboard.layouts.length > 1) {
                    keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length;
                }
            }
            Keys.onReturnPressed: advance()
            Keys.onEnterPressed: advance()
            Keys.onSpacePressed: advance()
            Accessible.onPressAction: advance()

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
                textFormat: Text.PlainText
            }
            MouseArea {
                anchors.fill: parent
                onClicked: keyboardPill.advance()
            }
        }

        // The board's accessibility button, for the aid SDDM lets a theme offer: the on-screen
        // keyboard. Shown where VirtualKeyboard.qml loaded.
        Rectangle {
            id: onScreenKeyboard
            visible: inputPanel.item !== null
            width: 34
            height: 34
            radius: 17
            color: "#14ffffff"
            Accessible.name: qsTr("On-screen keyboard")
            Accessible.role: Accessible.Button
            Accessible.checkable: true
            Accessible.checked: inputPanel.item !== null && inputPanel.item.activated
            activeFocusOnTab: true
            enabled: root.interactive && !root.authenticating
            border.color: activeFocus ? "#6aa9ff" : "transparent"
            border.width: activeFocus ? 2 : 0
            function toggle() {
                if (!enabled || inputPanel.item === null) {
                    return;
                }
                inputPanel.item.activated = !inputPanel.item.activated;
                // The keys go to the focused field, so give it the focus before the keyboard shows
                card.focusPassword();
            }
            Keys.onReturnPressed: toggle()
            Keys.onEnterPressed: toggle()
            Keys.onSpacePressed: toggle()
            Accessible.onPressAction: toggle()

            // The board's figure (24-unit grid at 18 px, stroke 1.8)
            Canvas {
                anchors.centerIn: parent
                width: 18
                height: 18
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.save();
                    ctx.scale(width / 24, height / 24);
                    ctx.strokeStyle = "#e8ebf4";
                    ctx.lineWidth = 1.8;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    ctx.beginPath();
                    ctx.arc(12, 4.5, 1.5, 0, Math.PI * 2);
                    ctx.moveTo(5, 8);
                    ctx.lineTo(12, 9.5);
                    ctx.lineTo(19, 8);
                    ctx.moveTo(12, 9.5);
                    ctx.lineTo(12, 14);
                    ctx.lineTo(9, 20);
                    ctx.moveTo(12, 14);
                    ctx.lineTo(15, 20);
                    ctx.stroke();
                    ctx.restore();
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: onScreenKeyboard.toggle()
            }
        }
    }

    // ---- The sign-in card (520,210 at 1440 x 900: centred, 400 wide) ----
    LoginCard {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        // Above the on-screen keyboard while it shows; it covers the user row and the footer then
        y: root.keyboardShown
           ? Math.max(0, Math.min(Math.round(parent.height * 210 / 900), inputPanel.y - height - 16))
           : Math.max(0, Math.min(Math.round(parent.height * 210 / 900),
                                  root.footerTop - users.height - height - 32))
        width: 400
        busy: root.authenticating
        allowInput: root.interactive
        heightBudget: Math.max(0, root.footerTop - users.height - 32)
        avatarSource: root.personIcon
        avatarLetter: root.personLetter
        personName: root.personName
        onLoginRequested: (user, password) => root.login(user, password)
    }

    // ---- The user row (y 600 of 900: two thirds down, centred) ----
    UserSwitcher {
        id: users
        busy: root.authenticating
        allowInput: root.interactive
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(card.y + card.height + 16,
                    Math.min(Math.round(parent.height * 600 / 900), root.footerTop - height - 16))
        onUserChosen: (index, user, icon, name, letter, needsPassword) => {
            card.message = "";
            card.clearPassword();
            card.clearUsername();
            root.loginName = user;
            root.personIcon = icon;
            root.personName = name;
            root.personLetter = letter;
            card.promptName = false;
            card.passwordRequired = needsPassword;
            card.focusPassword();
        }
        onOtherRequested: {
            card.message = "";
            card.clearPassword();
            root.loginName = "";
            root.personIcon = "";
            root.personName = "";
            root.personLetter = "?";
            card.promptName = true;
            card.passwordRequired = true;
            card.focusPassword();
        }
    }

    Component.onCompleted: {
        refreshPrimary();
        refreshAuthLock();
        initUsers();
    }

    // ---- The session pill (bottom left) ----
    SessionPill {
        id: session
        busy: root.authenticating
        allowInput: root.interactive
        x: 32
        maximumWidth: Math.max(0, (powerButtons.width > 0 ? powerButtons.x - 16 : root.width - 32) - x)
        menuBottomLimit: root.footerTop
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
    }

    // ---- The power buttons (bottom right) ----
    PowerBar {
        id: powerButtons
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 32
        anchors.bottomMargin: 28
    }

    // ---- Qt's virtual keyboard, along the bottom while it shows ----
    Loader {
        id: inputPanel
        z: 1
        width: parent.width
        y: root.keyboardShown ? root.height - height : root.height
        sourceComponent: root.keyboardComponent !== null && root.keyboardComponent.status === Component.Ready
                         ? root.keyboardComponent : null
    }
}
