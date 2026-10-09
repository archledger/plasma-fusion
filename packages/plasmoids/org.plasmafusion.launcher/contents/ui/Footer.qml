/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T
import org.kde.coreaddons as KCoreAddons
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.sessions as Sessions

// User row and session buttons (62 px, darker band, 1 px top edge). The band spans the
// whole card width and follows the card's bottom corner radius. Its height (set by the card),
// the account button and the text follow the user's text size; the avatar and the round
// session buttons keep their size.
FocusScope {
    id: footer

    property FusionColors pal
    property FusionMetrics metrics
    property var launcher
    property real cornerRadius: 21

    readonly property alias firstButton: accountButton
    readonly property alias lastButton: powerButton

    signal exitTop()
    signal tabFromLast()
    signal backtabFromFirst()

    implicitHeight: metrics.px(62)

    KCoreAddons.KUser {
        id: user
    }

    Sessions.SessionManagement {
        id: session
    }

    readonly property string displayName: user.fullName.length > 0 ? user.fullName : user.loginName

    Kirigami.ShadowedRectangle {
        anchors.fill: parent
        color: footer.pal.footer
        corners.topLeftRadius: 0
        corners.topRightRadius: 0
        corners.bottomLeftRadius: footer.cornerRadius
        corners.bottomRightRadius: footer.cornerRadius
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: footer.pal.footerEdge
    }

    // Avatar, name and account type. Opens the Users settings page.
    T.AbstractButton {
        id: accountButton
        // The avatar sits 24 px from the card edge (board); the hover pill reaches 6 px around it.
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: accountRow.implicitWidth + footer.metrics.px(20)
        implicitHeight: footer.metrics.px(44)
        hoverEnabled: true
        focusPolicy: Qt.TabFocus
        Accessible.role: Accessible.Button
        Accessible.name: footer.displayName
        Accessible.description: i18nc("@info:tooltip", "Account settings, Switch User and Log Out")
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Keys.onBacktabPressed: footer.backtabFromFirst()
        // As the Windows account menu and the stock launcher's leave entries: the account's
        // settings, then Switch User and Log Out where the session allows them.
        onClicked: accountMenu.openRelative()

        PlasmaExtras.Menu {
            id: accountMenu
            visualParent: accountButton
            placement: PlasmaExtras.Menu.TopPosedLeftAlignedPopup
            PlasmaExtras.MenuItem {
                text: i18nc("@action:inmenu", "Account Settings…")
                icon: "user-identity"
                onClicked: {
                    footer.launcher.close();
                    KCMUtils.KCMLauncher.openSystemSettings("kcm_users");
                }
            }
            PlasmaExtras.MenuItem {
                text: i18nc("@action:inmenu", "Switch User")
                icon: "system-switch-user"
                visible: session.canSwitchUser
                onClicked: {
                    footer.launcher.close();
                    session.switchUser();
                }
            }
            PlasmaExtras.MenuItem {
                text: i18nc("@action:inmenu", "Log Out")
                icon: "system-log-out"
                visible: session.canLogout
                onClicked: {
                    footer.launcher.close();
                    session.requestLogout();
                }
            }
        }

        background: Rectangle {
            radius: height / 2
            color: accountButton.hovered ? footer.pal.tint(0.05) : "transparent"
            antialiasing: true

            FocusRing {
                visible: accountButton.visualFocus
                baseRadius: accountButton.height / 2
                ringColor: footer.pal.focusRing
            }
        }

        contentItem: Item {
            Row {
                id: accountRow
                x: footer.metrics.px(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: footer.metrics.px(12)

                Item {
                    width: 36
                    height: 36

                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: footer.pal.avatar
                        antialiasing: true
                        visible: face.status !== Image.Ready

                        FusionText {
                            anchors.centerIn: parent
                            text: footer.displayName.length > 0 ? footer.displayName.charAt(0).toUpperCase() : ""
                            color: "#ffffff"
                            metrics: footer.metrics
                            px: 15
                            weight: 800
                        }
                    }

                    Kirigami.ShadowedTexture {
                        anchors.fill: parent
                        radius: 18
                        color: "transparent"
                        visible: face.status === Image.Ready
                        source: Image {
                            id: face
                            source: user.faceIconUrl
                            sourceSize.width: 72
                            sourceSize.height: 72
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                            visible: false
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    FusionText {
                        text: footer.displayName
                        color: footer.pal.text
                        metrics: footer.metrics
                        px: 13
                        weight: 800
                    }

                    FusionText {
                        text: i18nc("@info kind of user account", "Local account")
                        color: footer.pal.muted
                        metrics: footer.metrics
                        px: 11.5
                    }
                }
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        RoundButton {
            id: lockButton
            pal: footer.pal
            glyph: "lock"
            text: i18nc("@action:button", "Lock")
            enabled: session.canLock
            onClicked: {
                footer.launcher.close();
                session.lock();
            }
        }

        RoundButton {
            id: sleepButton
            pal: footer.pal
            glyph: "sleep"
            text: i18nc("@action:button", "Sleep")
            // Also where only hibernation is possible: the button then opens its menu.
            enabled: session.canSuspend || session.canHibernate
            onClicked: {
                if (!session.canSuspend) {
                    sleepMenu.offer();
                    return;
                }
                footer.launcher.close();
                session.suspend();
            }
            // Hibernate, where the system offers it: right-click, press and hold or the Menu key.
            onPressAndHold: sleepMenu.offer()
            Keys.onMenuPressed: sleepMenu.offer()
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: sleepMenu.offer()
            }
            PlasmaExtras.Menu {
                id: sleepMenu
                visualParent: sleepButton
                placement: PlasmaExtras.Menu.TopPosedRightAlignedPopup
                function offer(): void {
                    if (session.canHibernate) {
                        openRelative();
                    }
                }
                PlasmaExtras.MenuItem {
                    text: i18nc("@action:inmenu", "Sleep")
                    icon: "system-suspend"
                    enabled: session.canSuspend
                    onClicked: {
                        footer.launcher.close();
                        session.suspend();
                    }
                }
                PlasmaExtras.MenuItem {
                    text: i18nc("@action:inmenu", "Hibernate")
                    icon: "system-suspend-hibernate"
                    onClicked: {
                        footer.launcher.close();
                        session.hibernate();
                    }
                }
            }
        }

        RoundButton {
            id: restartButton
            pal: footer.pal
            glyph: "restart"
            text: i18nc("@action:button", "Restart")
            enabled: session.canReboot
            onClicked: {
                footer.launcher.close();
                session.requestReboot();
            }
        }

        RoundButton {
            id: powerButton
            pal: footer.pal
            glyph: "power"
            danger: true
            text: i18nc("@action:button", "Shut Down")
            enabled: session.canShutdown
            Keys.onTabPressed: footer.tabFromLast()
            onClicked: {
                footer.launcher.close();
                session.requestShutdown();
            }
        }
    }

    Keys.onUpPressed: footer.exitTop()
    Keys.onLeftPressed: event => {
        event.accepted = footer.moveFocus(-1);
    }
    Keys.onRightPressed: event => {
        event.accepted = footer.moveFocus(1);
    }

    function moveFocus(step: int): bool {
        const order = [accountButton, lockButton, sleepButton, restartButton, powerButton].filter(b => b.enabled);
        const at = order.findIndex(b => b.activeFocus);
        const next = at + step;
        if (at < 0 || next < 0 || next >= order.length) {
            return false;
        }
        order[next].forceActiveFocus(Qt.TabFocusReason);
        return true;
    }
}
