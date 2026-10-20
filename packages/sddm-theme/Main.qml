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
    // SDDM's login call is asynchronous; keep one request and its displayed identity stable.
    property bool authenticating: false
    // primaryScreen is a creation-time snapshot; screenModel.primary reads the current primary.
    // SDDM 0.21 never emits primaryChanged, so poll the getter at a login-screen pace.
    property bool primaryNow: primaryScreen === true
    property bool primaryInitialized: false
    // SDDM exposes no cross-engine pending state, so a handoff waits briefly before accepting
    // input instead of submitting into a request that may still run on the previous primary view.
    property bool handoffReady: true
    readonly property bool interactive: primaryNow && handoffReady
    readonly property real footerTop: Math.min(session.y, powerButtons.y)

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
            handoffReady = false;
            handoffTimer.restart();
            initUsers();
        } else {
            handoffReady = false;
            handoffTimer.stop();
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
        onTriggered: root.refreshPrimary()
    }
    Timer {
        id: handoffTimer
        interval: 2000
        repeat: false
        onTriggered: root.handoffReady = true
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
        authenticating = true;
        card.message = qsTr("Signing in…");
        // Do not leave a revealed credential on screen while PAM is pending.
        card.clearPassword();
        sddm.login(who, card.passwordRequired ? password : "", session.index);
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            authenticating = false;
            card.message = qsTr("Login failed");
            card.clearPassword();
            // clearPassword focuses the name field for Other user; only the password was wrong.
            card.focusPasswordField();
        }
        function onLoginSucceeded() {
            authenticating = false;
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

    // ---- The sign-in card (520,210 at 1440 x 900: centred, 400 wide) ----
    LoginCard {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(0, Math.min(Math.round(parent.height * 210 / 900),
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
}
