// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.sessions
import org.kde.plasma.workspace.dbus as DBus

// Restart or Shut Down from the lock screen (survey U6, KDE wishlist 336369), pushed on the
// prompt's stack by the power buttons, which show only where SessionManagement allows the action
// (logind's CanReboot / CanPowerOff and the KAuthorized "logout" restriction, as on the log-out
// screen). The log-out screen cannot open over the lock screen (SessionManagement does not prompt
// while the screen saver is active), so this page asks instead and then requests the action without
// a prompt: ksmserver closes the session (an app with unsaved work waits for an answer, which needs
// unlocking) and asks logind to restart or power off.
//
// It reads logind's inhibitors for shutdown: a "block" inhibitor makes logind refuse the request
// after the session has already closed (systemd 259, "Operation denied due to active block
// inhibitor"), so while one is held the action stays off and the page says a program is blocking
// it; for "block-weak" ones it says a program is busy. The list is read again every 2 s while the
// page is shown.
//
// Whoever stands at the locked screen sees this page without unlocking, so it names no program,
// reason or user: logind lists every user's inhibitors with their holder and reason, and the stock
// lock screens show neither those nor the log-out screen's count of other logged-in users (Plasma
// 6.7 and 6.8 offer no Restart or Shut Down there, and do not open the log-out screen while the
// screen is locked, plasma-workspace sessionmanagement.cpp requestLogoutPrompt).
FocusScope {
    id: root
    objectName: "powerConfirm"

    // "reboot" or "shutdown"
    required property string action
    required property FusionMetrics metrics
    property SessionManagement session: null
    readonly property bool reboot: action === "reboot"

    // Inhibitors of shutdown: [{strong}] ("block" or "block-weak"), without who holds them.
    property var blockers: []
    readonly property bool blocked: blockers.some(b => b.strong)
    property bool requested: false

    signal done()
    signal announcement(string text, bool urgent)

    focus: true

    function refresh(): void {
        DBus.SystemBus.asyncCall({
            "service": "org.freedesktop.login1",
            "path": "/org/freedesktop/login1",
            "iface": "org.freedesktop.login1.Manager",
            "member": "ListInhibitors",
            "arguments": []
        }, reply => {
            root.blockers = root.shutdownBlockers(reply.value);
        }, reply => {
            // Without logind's list (no logind, refused) nothing is known to block.
            console.warn("lockscreen: logind's inhibitors not read: " + reply.error.name);
            root.blockers = [];
        });
    }
    // ListInhibitors: a(ssssuu) what (":"-separated), who, why, mode, uid, pid. Plasma's D-Bus
    // module hands each field of logind's reply over as a typed value ({"value": ...}; seen in the
    // greeter on Plasma 6.7.5), a plain value is taken as well.
    function shutdownBlockers(list: var): var {
        const plain = v => v !== null && typeof v === "object" && "value" in v ? v.value : v;
        const out = [];
        for (const entry of (list || [])) {
            const e = plain(entry);
            const f = (Array.isArray(e) ? e : Object.values(e || {})).map(plain);
            const what = String(f[0] || "").split(":");
            const mode = String(f[3] || "");
            if (what.indexOf("shutdown") < 0 || (mode !== "block" && mode !== "block-weak")) {
                continue;
            }
            out.push({ strong: mode === "block" });
        }
        return out;
    }
    // A label without its "&" mnemonic marker ("&&" is a literal "&").
    function plainLabel(label: string): string {
        return label.replace(/&(&?)/g, "$1");
    }
    function confirm(): void {
        if (blocked || requested || !session) {
            return;
        }
        requested = true;
        root.announcement(statusText.text, false);
        if (reboot) {
            session.requestReboot(SessionManagement.ConfirmationMode.Skip);
        } else {
            session.requestShutdown(SessionManagement.ConfirmationMode.Skip);
        }
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.visible && !root.requested
        onTriggered: root.refresh()
    }
    // The session normally ends within seconds; when it does not (an app cancelled the log-out,
    // which ksmserver reports as a notification), the prompt comes back.
    Timer {
        interval: 30000
        running: root.requested
        onTriggered: {
            root.requested = false;
            root.done();
        }
    }

    Keys.onEscapePressed: event => {
        event.accepted = true;
        if (!root.requested) {
            root.done();
        }
    }

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(Kirigami.Units.gridUnit, Math.round(root.height * 210 / PfStyle.boardHeight))
        width: Math.min(root.metrics.px(400), root.width - 64)
        spacing: root.metrics.px(16)

        Accessible.role: Accessible.Dialog
        Accessible.name: title.text

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 64
            height: 64
            radius: 32
            antialiasing: true
            color: root.reboot ? PfStyle.chipFill : PfStyle.shutDownFill
            border.width: 1
            border.color: root.reboot ? PfStyle.chipBorder : PfStyle.shutDownFill
            LineIcon {
                anchors.centerIn: parent
                size: 26
                path: root.reboot ? PfStyle.iconRestart : PfStyle.iconShutDown
                color: root.reboot ? PfStyle.text : "#ffffff"
            }
        }
        Text {
            id: title
            objectName: "powerConfirmTitle"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.reboot ? i18nd("plasma_shell_org.plasmafusion.lockshell", "Restart now?")
                              : i18nd("plasma_shell_org.plasmafusion.lockshell", "Shut down now?")
            color: PfStyle.text
            font.family: PfStyle.displayFont
            font.pixelSize: root.metrics.font(28)
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: i18nd("plasma_shell_org.plasmafusion.lockshell",
                        "Open apps are closed first. An app with unsaved work waits until you unlock and answer it.")
            color: PfStyle.textSecondary
            font.family: PfStyle.uiFont
            font.pixelSize: root.metrics.font(13)
            font.weight: Font.DemiBold
            font.styleName: PfStyle.bold
            textFormat: Text.PlainText
        }
        Text {
            objectName: "powerConfirmBlockers"
            width: parent.width
            visible: root.blockers.length > 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: !root.blocked ? (root.reboot ? i18nd("plasma_shell_org.plasmafusion.lockshell", "A program is busy. Restarting now may interrupt it.")
                                               : i18nd("plasma_shell_org.plasmafusion.lockshell", "A program is busy. Shutting down now may interrupt it."))
                : root.reboot ? i18nd("plasma_shell_org.plasmafusion.lockshell", "A program is blocking a restart. Try again when it has finished.")
                : i18nd("plasma_shell_org.plasmafusion.lockshell", "A program is blocking a shutdown. Try again when it has finished.")
            color: PfStyle.warning
            font.family: PfStyle.uiFont
            font.pixelSize: root.metrics.font(13)
            font.weight: Font.Bold
            font.styleName: PfStyle.bold
            textFormat: Text.PlainText
        }
        Text {
            id: statusText
            width: parent.width
            visible: root.requested
            horizontalAlignment: Text.AlignHCenter
            text: root.reboot ? i18nd("plasma_shell_org.plasmafusion.lockshell", "Restarting…")
                              : i18nd("plasma_shell_org.plasmafusion.lockshell", "Shutting down…")
            color: PfStyle.textMuted
            font.family: PfStyle.uiFont
            font.pixelSize: root.metrics.font(13)
            font.weight: Font.DemiBold
            font.styleName: PfStyle.bold
            textFormat: Text.PlainText
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.metrics.px(12)

            PillButton {
                id: cancelButton
                objectName: "powerCancelButton"
                text: i18nd("plasma_shell_org.plasmafusion.lockshell", "Cancel")
                enabled: !root.requested
                onClicked: root.done()
            }
            PillButton {
                id: confirmButton
                objectName: "powerConfirmButton"
                // The log-out screen's strings without their mnemonic: Alt+R / Alt+S open this
                // question from the power row, and the same chord pressed again or held (key
                // repeat) would answer it at once. Return, Space or a click answer it.
                text: root.plainLabel(root.reboot ? i18nd(PfStyle.logoutDomain, "&Restart")
                                                  : i18nd(PfStyle.logoutDomain, "&Shut Down"))
                mnemonic: false
                fill: root.reboot ? PfStyle.accentStrong : PfStyle.shutDownFill
                hoverFill: root.reboot ? PfStyle.accentStrongHover : PfStyle.shutDownFillHover
                foreground: root.reboot ? PfStyle.textOnAccent : "#ffffff"
                enabled: !root.blocked && !root.requested
                // The chosen action has the focus, as on the log-out screen; Escape cancels.
                focus: true
                onClicked: root.confirm()
            }
        }
    }

    // A 44 px pill: the Login board's chip (Cancel) or a filled action button.
    component PillButton: T.AbstractButton {
        id: pillButton

        property color fill: PfStyle.chipFill
        property color hoverFill: PfStyle.chipFillHover
        property color foreground: PfStyle.text
        // Kirigami's mnemonic underline (the button's own Alt+letter comes from an "&" in text).
        property bool mnemonic: true

        width: Math.max(root.metrics.px(140), label.implicitWidth + root.metrics.px(40))
        height: root.metrics.tablet ? 48 : 44
        hoverEnabled: true
        focusPolicy: Qt.TabFocus
        opacity: enabled ? 1 : 0.45

        Accessible.name: Kirigami.MnemonicData.plainTextLabel

        Kirigami.MnemonicData.enabled: mnemonic && enabled && visible
        Kirigami.MnemonicData.controlType: Kirigami.MnemonicData.SecondaryControl
        Kirigami.MnemonicData.label: text

        background: Rectangle {
            radius: height / 2
            antialiasing: true
            color: pillButton.hovered || pillButton.visualFocus ? pillButton.hoverFill : pillButton.fill
            border.width: Qt.colorEqual(pillButton.fill, PfStyle.chipFill) ? 1 : 0
            border.color: PfStyle.chipBorder
            scale: pillButton.down ? 0.97 : 1

            FocusRing {
                visible: pillButton.visualFocus
            }
        }
        contentItem: Text {
            id: label
            text: pillButton.Kirigami.MnemonicData.richTextLabel
            textFormat: Text.StyledText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: pillButton.foreground
            font.family: PfStyle.uiFont
            font.pixelSize: root.metrics.font(14)
            font.weight: Font.Bold
            font.styleName: PfStyle.bold
        }

        // Only a fresh press counts: the repeats of a key held on the power button that opened
        // the question (Return, Space) reach this button once it has the focus, and must not
        // answer it.
        Keys.onEnterPressed: event => {
            if (!event.isAutoRepeat) {
                clicked();
            }
        }
        Keys.onReturnPressed: event => {
            if (!event.isAutoRepeat) {
                clicked();
            }
        }
        Keys.onSpacePressed: event => {
            event.accepted = event.isAutoRepeat;
        }
        Keys.onReleased: event => {
            event.accepted = event.key === Qt.Key_Space && event.isAutoRepeat;
        }
    }
}
