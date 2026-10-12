/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker

// The ways to unlock that the Plasma 6.8 greeter offers (kscreenlocker's AuthenticatorModel):
// the password always, and a smartcard, the fingerprint reader, the face or a security key where
// the system has the PAM service and the user turned it on (kscreenlockerrc [Authenticators]).
// The stock 6.8 lock screen shows them as a row of icon buttons; here each other way is a link in
// the hint line under the field, as the Login board draws "Use fingerprint" ("Use security key",
// "Use password"). The greeter runs the chosen way only and keeps it for the next lock once it has
// unlocked. Loaded by MainBlock on Plasma 6.8 and later only: Plasma 6.7's greeter has none of
// these types.
Flow {
    id: choice
    objectName: "authenticatorChoice"

    // The PamAuthenticators object (context property "authenticator").
    required property QtObject authenticatorObject
    required property FusionMetrics metrics
    // The fingerprint reader runs beside every other way and has its own hint (MainBlock's
    // "Use fingerprint"); while it does, choosing the fingerprint way alone would only take the
    // password field away, so it gets no link.
    property bool fingerprintBeside: false

    // qmllint disable missing-property
    readonly property int current: authenticatorObject.authenticator
    // qmllint enable missing-property
    // The delegate of the way in use (null until the model has it).
    property Item currentWay: null
    readonly property bool passwordField: !currentWay || currentWay.passwordField
    readonly property bool expectingPrompt: !currentWay || currentWay.expectingPrompt
    readonly property bool showPrompt: !!currentWay && currentWay.showPrompt
    readonly property string currentIcon: currentWay ? currentWay.iconName : ""
    readonly property string statusText: currentWay ? statusFor(currentWay.type, currentWay.tooltip) : ""
    readonly property int count: ways.count
    readonly property bool hasLinks: linkCount > 0
    property int linkCount: 0

    // A way stopped working (its PAM service failed again and again or reports it is not
    // available): the stock lock screen's message, then the password again.
    signal defunct(string message)
    // A link was used (the field takes the focus again, or the prompt stays up).
    signal chosen()

    spacing: metrics.px(14)
    layoutDirection: Qt.RightToLeft

    function linkFor(type: int, tooltip: string): string {
        switch (type) {
        case ScreenLocker.Authenticators.Regular:
            return i18nd("plasma_shell_org.plasmafusion.lockshell", "Use password");
        case ScreenLocker.Authenticators.Smartcard:
            return i18nd("plasma_shell_org.plasmafusion.lockshell", "Use smartcard");
        case ScreenLocker.Authenticators.Fingerprint:
            return i18nd("plasma_shell_org.plasmafusion.lockshell", "Use fingerprint");
        case ScreenLocker.Authenticators.Face:
            return i18nd("plasma_shell_org.plasmafusion.lockshell", "Use face");
        case ScreenLocker.Authenticators.Universal2Factor:
            return i18nd("plasma_shell_org.plasmafusion.lockshell", "Use security key");
        }
        return i18ndc("plasma_shell_org.plasmafusion.lockshell", "%1 is a way to unlock as the system names it", "Use %1", tooltip);
    }

    // What the pill says while a way without a password field is in use.
    function statusFor(type: int, tooltip: string): string {
        switch (type) {
        case ScreenLocker.Authenticators.Fingerprint:
            return i18nd("plasma_shell_org.plasmafusion.lockshell", "Unlock with your fingerprint");
        case ScreenLocker.Authenticators.Face:
            return i18nd("plasma_shell_org.plasmafusion.lockshell", "Unlock with your face");
        case ScreenLocker.Authenticators.Universal2Factor:
            return i18nd("plasma_shell_org.plasmafusion.lockshell", "Unlock with your security key");
        }
        return i18ndc("plasma_shell_org.plasmafusion.lockshell", "%1 is a way to unlock as the system names it", "Unlock with %1", tooltip);
    }

    function choose(type: int): void {
        // qmllint disable missing-property
        if (authenticatorObject.authenticator !== type) {
            authenticatorObject.authenticator = type;
        }
        // qmllint enable missing-property
    }

    // Finds the way in use. The greeter starts with the way that unlocked last time; when the
    // model no longer offers it (turned off since, or its PAM service is gone) or it does not work,
    // the password is used, so that the screen never waits for a way that cannot unlock.
    function sync(): void {
        let found = null;
        let links = 0;
        for (let i = 0; i < ways.count; ++i) {
            const way = ways.itemAt(i);
            if (!way) {
                continue;
            }
            if (way.type === current) {
                found = way;
            } else if (way.shown) {
                ++links;
            }
        }
        linkCount = links;
        if (ways.count > 0 && (!found || !found.functional) && current !== ScreenLocker.Authenticators.Regular) {
            choose(ScreenLocker.Authenticators.Regular);
            return;
        }
        currentWay = found;
    }
    onCurrentChanged: Qt.callLater(sync)
    onFingerprintBesideChanged: Qt.callLater(sync)
    Component.onCompleted: Qt.callLater(sync)

    Repeater {
        id: ways
        model: ScreenLocker.AuthenticatorModel
        onCountChanged: Qt.callLater(choice.sync)

        delegate: Text {
            id: link

            required property int type
            required property string iconName
            required property bool passwordField
            required property bool expectingPrompt
            required property string tooltip
            required property bool showPrompt
            required property bool functional

            readonly property bool shown: type !== choice.current && ways.count > 1
                && !(type === ScreenLocker.Authenticators.Fingerprint && choice.fingerprintBeside)

            function activate(): void {
                if (!functional) {
                    return;
                }
                choice.choose(type);
                choice.chosen();
            }

            objectName: "authenticatorLink" + type
            visible: shown
            enabled: functional
            text: choice.linkFor(type, tooltip)
            // A way that stopped working stays listed in the warning colour, as the stock picker
            // shows it in the negative colour, and does nothing.
            color: functional ? PfStyle.link : PfStyle.warning
            opacity: functional ? 1 : 0.7
            font.family: PfStyle.uiFont
            font.pixelSize: choice.metrics.font(12)
            font.weight: Font.DemiBold
            font.styleName: PfStyle.bold
            font.underline: linkHover.hovered && functional
            textFormat: Text.PlainText

            activeFocusOnTab: functional
            Accessible.role: Accessible.Link
            Accessible.name: text
            Accessible.description: functional ? tooltip
                : i18nd("plasma_shell_org.plasmafusion.lockshell", "Not working")
            Accessible.onPressAction: activate()
            Keys.onSpacePressed: activate()
            Keys.onReturnPressed: activate()
            Keys.onEnterPressed: activate()

            onShownChanged: Qt.callLater(choice.sync)
            onFunctionalChanged: {
                // The model also reports the first value; only a way that stops working counts.
                if (functional) {
                    return;
                }
                if (type === choice.current) {
                    choice.defunct(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status",
                        "This authentication method is not functioning correctly. Please try another method, and check your system configuration."));
                }
                Qt.callLater(choice.sync);
            }

            HoverHandler {
                id: linkHover
                cursorShape: link.functional ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
            TapHandler {
                onTapped: link.activate()
            }
            FocusRing {
                anchors.margins: -3
                controlRadius: Kirigami.Units.cornerRadius
                visible: link.activeFocus
            }
        }
    }
}
