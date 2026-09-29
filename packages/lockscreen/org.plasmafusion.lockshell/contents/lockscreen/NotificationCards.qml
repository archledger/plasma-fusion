// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Lock board: notifications that arrived while locked, one 400 x 56 glass card per
// application (radius 16, 8 px apart): app icon (30 px), name (800), "N new notifications ·
// hidden while locked" and the time of the newest one. Content stays hidden unless the user
// opts in to titles (config "showNotificationSummaries"); bodies and actions are never shown.
Column {
    id: cards

    property Backdrop backdrop: null
    property var groups: []
    property int maximumCards: 3
    property bool showSummaries: false

    spacing: 8
    width: 400

    Accessible.role: Accessible.List
    Accessible.name: i18nd("plasma_shell_org.plasmafusion.lockshell", "Notifications while locked")

    Repeater {
        model: cards.groups.slice(0, Math.max(0, cards.maximumCards))

        GlassPanel {
            id: card

            required property var modelData

            readonly property string appName: modelData.appName.length > 0 ? modelData.appName
                                                                            : i18nd("plasma_shell_org.plasmafusion.lockshell", "Notification")
            readonly property string detail: {
                if (cards.showSummaries && modelData.summary.length > 0) {
                    return modelData.count > 1
                        ? i18nd("plasma_shell_org.plasmafusion.lockshell", "%1 · and %2 more", modelData.summary, modelData.count - 1)
                        : modelData.summary;
                }
                return i18ndp("plasma_shell_org.plasmafusion.lockshell",
                              "New notification · hidden while locked",
                              "%1 new notifications · hidden while locked", modelData.count);
            }
            readonly property string timeText: Qt.locale().toString(modelData.latest, Qt.locale().timeFormat(Locale.ShortFormat))

            backdrop: cards.backdrop
            width: cards.width
            height: 56
            radius: 16

            Accessible.role: Accessible.ListItem
            Accessible.name: appName + ", " + detail + ", " + timeText

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12

                Kirigami.Icon {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    source: card.modelData.iconName.length > 0 ? card.modelData.iconName : "preferences-desktop-notification-bell"
                    fallback: "preferences-desktop-notification-bell"
                    roundToIconSize: false
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: card.appName
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: PfStyle.text
                        font.family: PfStyle.uiFont
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        font.styleName: PfStyle.extraBold
                        textFormat: Text.PlainText
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.detail
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: PfStyle.textSecondary
                        font.family: PfStyle.uiFont
                        font.pixelSize: 12
                        textFormat: Text.PlainText
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: card.timeText
                    color: PfStyle.textTertiary
                    font.family: PfStyle.uiFont
                    font.pointSize: 8.625 // 11.5 px at 96 dpi
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
