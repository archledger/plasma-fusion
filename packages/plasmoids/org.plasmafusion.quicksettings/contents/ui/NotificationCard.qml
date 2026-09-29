// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "components"
import "components/Icons.js" as Icons

// One notification of the list (Quick Settings board, notification cards):
// app icon and name, time, summary, body, job progress and action buttons.
Rectangle {
    id: card

    required property FusionPalette pal
    required property var model
    required property int index
    property double now: Date.now()

    signal actionInvoked(string name)
    signal closeClicked()
    signal killJobClicked()

    // org.kde.notificationmanager Notifications enums
    readonly property bool isJob: model.type === 2
    readonly property bool jobRunning: isJob && model.jobState !== 0
    readonly property var actionNames: model.actionNames || []
    readonly property var actionLabels: model.actionLabels || []
    readonly property bool primaryAction: model.urgency === 4 || model.timeout === 0
    readonly property bool hovered: cardHover.hovered
    readonly property bool closable: !jobRunning && model.closable !== false
    readonly property bool showClose: closable && (hovered || closeButton.activeFocus)
    // Keyboard focus is on one of this card's buttons (the list scrolls it into view).
    readonly property bool focusInside: {
        for (let item = Window.activeFocusItem; item; item = item.parent) {
            if (item === card) {
                return true;
            }
        }
        return false;
    }

    function relativeTime(created, updated) {
        let date = updated && !isNaN(updated.getTime()) ? updated : created;
        if (!date || isNaN(date.getTime())) {
            return "";
        }
        const seconds = Math.round((card.now - date.getTime()) / 1000);
        if (seconds < 60) {
            return i18nc("@info notification time", "now");
        }
        const minutes = Math.round(seconds / 60);
        if (minutes < 60) {
            return i18ncp("@info notification time", "%1 min ago", "%1 min ago", minutes);
        }
        const hours = Math.round(minutes / 60);
        if (hours < 24) {
            return i18ncp("@info notification time", "%1 h ago", "%1 h ago", hours);
        }
        return Qt.formatDate(date, Qt.locale().dateFormat(Locale.ShortFormat));
    }
    function cleanBody(text) {
        // The notification server hands over sanitised XHTML (an XML declaration and an
        // <html> wrapper around b/i/u/a/br/img/table). Text.StyledText draws the
        // declaration as an empty line, so unwrap it; images are not shown in the list.
        return String(text || "")
            .replace(/<\?xml[^>]*\?>/gi, "")
            .replace(/<\/?html>/gi, "")
            .replace(/<img[^>]*\/?>/gi, "")
            .replace(/\n/g, "<br>")
            .replace(/^(\s|<br\s*\/?>)+|(\s|<br\s*\/?>)+$/gi, "");
    }

    implicitHeight: column.implicitHeight + 28
    radius: 18
    color: pal.overlay(0.06)
    border.width: 1
    border.color: pal.overlay(0.08)

    HoverHandler {
        id: cardHover
    }
    TapHandler {
        enabled: !!card.model.hasDefaultAction
        onTapped: card.actionInvoked("default")
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 14
        }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            spacing: 8

            Kirigami.Icon {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                source: card.model.applicationIconName || card.model.iconName || "preferences-desktop-notification-bell"
            }
            FText {
                Layout.fillWidth: true
                pal: card.pal
                text: card.model.applicationName || ""
                color: card.pal.secondary
                px: 11.5
                font.weight: Font.ExtraBold
            }
            // Time, replaced by the close button on hover or keyboard focus. The button
            // stays in the tab chain (transparent) so keyboard users can close a card too.
            Item {
                Layout.preferredWidth: card.showClose ? closeButton.implicitWidth : timeLabel.implicitWidth
                Layout.preferredHeight: 22

                FText {
                    id: timeLabel
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !card.showClose
                    pal: card.pal
                    text: card.relativeTime(card.model.created, card.model.updated)
                    color: card.pal.tertiary
                    px: 11.5
                }
                IconButton {
                    id: closeButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: card.closable
                    opacity: card.showClose ? 1 : 0
                    pal: card.pal
                    size: 22
                    iconSize: 12
                    fill: "transparent"
                    iconPath: Icons.close
                    text: i18nc("@action:button", "Close notification")
                    toolTip: card.showClose ? text : ""
                    onClicked: card.closeClicked()
                }
            }
        }

        FText {
            Layout.fillWidth: true
            pal: card.pal
            visible: text.length > 0
            text: card.model.summary || ""
            px: 13.5
            font.weight: Font.ExtraBold
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }
        FText {
            Layout.fillWidth: true
            pal: card.pal
            visible: !card.isJob && text.length > 0
            text: card.cleanBody(card.model.body)
            textFormat: Text.StyledText
            color: card.pal.body
            linkColor: card.pal.link
            px: 12.5
            wrapMode: Text.Wrap
            maximumLineCount: 4
            onLinkActivated: link => Qt.openUrlExternally(link)
        }

        // Job progress (file copies and downloads)
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: card.isJob
            spacing: 10
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: card.pal.overlay(0.14)
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, card.model.percentage || 0)) / 100
                    height: parent.height
                    radius: 3
                    color: card.pal.accentSoft
                }
            }
            FText {
                pal: card.pal
                text: i18nc("@info job progress", "%1%", card.model.percentage || 0)
                color: card.pal.secondary
                px: 11.5
            }
            TextButton {
                visible: card.jobRunning && !!card.model.killable
                pal: card.pal
                implicitHeight: 26
                radius: 13
                fontSize: 12
                text: i18nc("@action:button cancel a file transfer", "Cancel")
                onClicked: card.killJobClicked()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            visible: !card.isJob && card.actionNames.length > 0
            spacing: 8

            Repeater {
                model: card.actionNames.length
                delegate: TextButton {
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    pal: card.pal
                    implicitHeight: 32
                    radius: 10
                    fontSize: 12.5
                    primary: index === 0 && card.primaryAction
                    fontWeight: primary ? Font.ExtraBold : Font.Bold
                    text: card.actionLabels[index] || card.actionNames[index]
                    onClicked: card.actionInvoked(card.actionNames[index])
                }
            }
        }
    }
}
