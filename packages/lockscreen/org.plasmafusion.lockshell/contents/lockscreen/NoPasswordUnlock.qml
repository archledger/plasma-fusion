/*
    SPDX-FileCopyrightText: 2022 David Edmundson <davidedmundson@kde.org>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Shown when authentication succeeded without any prompt (for example an account without a
// password, or a face or token module that finished on its own): the user confirms with an
// explicit Unlock button, as in the Plasma lock screen.
FocusScope {
    id: root

    property var userListModel
    // Text scale and pixel grid of the lock screen window (set by LockScreenUi).
    required property FusionMetrics metrics
    readonly property var user: userListModel && userListModel.count > 0 ? userListModel.get(0) : null

    focus: true

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(Kirigami.Units.gridUnit, Math.round(root.height * 210 / PfStyle.boardHeight))
        width: Math.min(root.metrics.px(400), root.width - 64)
        spacing: root.metrics.px(22)

        UserHeader {
            anchors.horizontalCenter: parent.horizontalCenter
            metrics: root.metrics
            userName: root.user ? root.user.realName : ""
            userIcon: root.user ? root.user.icon : ""
        }

        T.AbstractButton {
            id: loginButton
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(root.metrics.px(340), parent.width)
            height: root.metrics.px(48)
            focus: true
            hoverEnabled: true
            text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button no-password unlock", "Unlock")

            Accessible.name: text

            background: Rectangle {
                radius: height / 2
                antialiasing: true
                color: loginButton.hovered || loginButton.visualFocus ? PfStyle.accentStrongHover : PfStyle.accentStrong

                FocusRing {
                    visible: loginButton.visualFocus
                }
            }
            contentItem: Item {
                Row {
                    anchors.centerIn: parent
                    spacing: root.metrics.px(10)
                    LineIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: root.metrics.px(18)
                        path: PfStyle.iconUnlock
                        color: PfStyle.textOnAccent
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: loginButton.text
                        color: PfStyle.textOnAccent
                        font.family: PfStyle.uiFont
                        font.pixelSize: root.metrics.font(14)
                        font.weight: Font.DemiBold
                        font.styleName: PfStyle.bold
                        textFormat: Text.PlainText
                    }
                }
            }

            onClicked: Qt.quit()
            Keys.onEnterPressed: clicked()
            Keys.onReturnPressed: clicked()
        }
    }

    Component.onCompleted: {
        forceActiveFocus();
    }
}
