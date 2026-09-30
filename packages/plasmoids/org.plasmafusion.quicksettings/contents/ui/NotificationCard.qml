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
// Text, the rows and buttons that hold it and the gaps follow the user's text size
// (`metrics`); the radius, the border, the progress bar and the close button do not.
// Touch mode (TABLET 4.6, ADAPTIVE 5.3): the close button is always shown (32 px drawn, 44 px
// target) beside the time, actions are 44 px tall, and a horizontal swipe dismisses the card
// (40 % of its width or 800 px/s; the card follows the finger).
Rectangle {
    id: card

    required property FusionPalette pal
    required property FusionMetrics metrics
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
    readonly property bool showClose: closable && (pal.touch || hovered || closeButton.activeFocus)
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

    implicitHeight: column.implicitHeight + 2 * column.anchors.margins
    Accessible.role: Accessible.ListItem
    Accessible.name: model.summary || model.applicationName || ""
    Accessible.description: model.applicationName || ""
    radius: 18
    color: pal.overlay(0.06)
    border.width: 1
    border.color: pal.overlay(0.08)

    HoverHandler {
        id: cardHover
    }

    // Swipe to dismiss (touch).
    transform: Translate {
        id: swipeShift
        x: 0
    }
    opacity: 1 - Math.min(0.6, Math.abs(swipeShift.x) / Math.max(1, width))
    DragHandler {
        id: swipe
        enabled: card.closable
        acceptedDevices: PointerDevice.TouchScreen
        target: null
        yAxis.enabled: false
        dragThreshold: 16
        property real lastX: 0
        property real lastTime: 0
        property real velocity: 0
        onActiveChanged: {
            if (active) {
                swipeBack.stop();
                velocity = 0;
                lastX = centroid.position.x;
                lastTime = Date.now();
                return;
            }
            const dx = swipeShift.x;
            if (Math.abs(dx) > card.width * 0.4 || Math.abs(velocity) > 800) {
                swipeOut.to = (dx !== 0 ? Math.sign(dx) : Math.sign(velocity)) * card.width;
                swipeOut.start();
            } else {
                swipeBack.start();
            }
        }
        onCentroidChanged: {
            if (!active) {
                return;
            }
            const now = Date.now();
            const x = centroid.position.x;
            if (now > lastTime) {
                velocity = (x - lastX) / (now - lastTime) * 1000;
            }
            lastX = x;
            lastTime = now;
            swipeShift.x = centroid.position.x - centroid.pressPosition.x;
        }
    }
    NumberAnimation {
        id: swipeBack
        target: swipeShift
        property: "x"
        to: 0
        duration: card.pal.motion.popupOut
        easing.type: card.pal.motion.standardEasing
    }
    NumberAnimation {
        id: swipeOut
        target: swipeShift
        property: "x"
        duration: card.pal.motion.popupOut
        easing.type: card.pal.motion.exitEasing
        onFinished: card.closeClicked()
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
            margins: card.metrics.px(14)
        }
        spacing: card.metrics.px(6)

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: card.metrics.px(22)
            spacing: card.metrics.px(8)

            Kirigami.Icon {
                Layout.preferredWidth: card.metrics.px(22)
                Layout.preferredHeight: card.metrics.px(22)
                source: card.model.applicationIconName || card.model.iconName || "preferences-desktop-notification-bell"
            }
            FText {
                Layout.fillWidth: true
                pal: card.pal
                metrics: card.metrics
                text: card.model.applicationName || ""
                color: card.pal.secondary
                px: 11.5
                font.weight: Font.ExtraBold
            }
            // Time, replaced by the close button on hover or keyboard focus (in touch mode
            // both are shown). The button stays in the tab chain (transparent) so keyboard
            // users can close a card too.
            Item {
                Layout.preferredWidth: card.pal.touch ? timeLabel.implicitWidth + card.metrics.px(4) + closeButton.implicitWidth
                                                      : card.showClose ? closeButton.implicitWidth : timeLabel.implicitWidth
                Layout.preferredHeight: card.metrics.px(22)

                FText {
                    id: timeLabel
                    anchors.right: card.pal.touch ? closeButton.left : parent.right
                    anchors.rightMargin: card.pal.touch ? card.metrics.px(4) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    visible: card.pal.touch || !card.showClose
                    pal: card.pal
                    metrics: card.metrics
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
                    size: card.pal.touch ? 32 : 22
                    iconSize: card.pal.touch ? 14 : 12
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
            metrics: card.metrics
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
            metrics: card.metrics
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
            Layout.topMargin: card.metrics.px(2)
            visible: card.isJob
            spacing: card.metrics.px(10)
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
                metrics: card.metrics
                text: i18nc("@info job progress", "%1%", card.model.percentage || 0)
                color: card.pal.secondary
                px: 11.5
            }
            TextButton {
                visible: card.jobRunning && !!card.model.killable
                pal: card.pal
                metrics: card.metrics
                fontSize: 12
                text: i18nc("@action:button cancel a file transfer", "Cancel")
                onClicked: card.killJobClicked()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: card.metrics.px(6)
            visible: !card.isJob && card.actionNames.length > 0
            spacing: card.metrics.px(8)

            Repeater {
                model: card.actionNames.length
                delegate: TextButton {
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    pal: card.pal
                    metrics: card.metrics
                    implicitHeight: card.pal.touch ? Math.max(44, card.metrics.px(32)) : card.metrics.px(32)
                    radius: card.pal.touch ? 12 : 10
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
