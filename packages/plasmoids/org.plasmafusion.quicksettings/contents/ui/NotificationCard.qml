// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "components"
import "components/Icons.js" as Icons
import "../code/notifications.js" as Notes

// One notification of the list (Quick Settings board, notification cards):
// app icon and name, time, summary, body, the notification's image, file thumbnail, job progress
// and action buttons. Images follow the stock Notifications applet's sizes: the notification's own
// image (or icon, when it is not the app's) beside the text at Plasma's large icon size, a file
// it links (a screenshot) as a preview strip of the "enormous" icon height, and images in the body
// below the text, fitted to the card and no taller than that strip.
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
    // A file of the notification was opened (its thumbnail).
    signal urlOpened(string url)

    // The row's data. While a removed row's card is torn down, `model` and this property read as
    // null, so every use is optional (`entry?.`).
    readonly property var entry: model || ({})
    // org.kde.notificationmanager Notifications enums
    readonly property bool isJob: entry?.type === 2
    readonly property bool jobRunning: isJob && entry?.jobState !== 0
    readonly property var actionNames: entry?.actionNames || []
    readonly property var actionLabels: entry?.actionLabels || []
    readonly property bool primaryAction: entry?.urgency === 4 || entry?.timeout === 0
    // The body's text and the images it carries (contents/code/notifications.js).
    readonly property var bodyParts: Notes.splitBody(entry?.body)
    readonly property var sideImage: Notes.sideImage(entry?.image, entry?.iconName, entry?.applicationIconName)
    readonly property var urls: entry?.urls || []
    readonly property string bodyText: bodyParts.text
    readonly property bool hovered: cardHover.hovered
    readonly property bool closable: !jobRunning && entry?.closable !== false
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
    implicitHeight: column.implicitHeight + 2 * column.anchors.margins
    Accessible.role: Accessible.ListItem
    Accessible.name: entry?.summary || entry?.applicationName || ""
    Accessible.description: entry?.applicationName || ""
    // The card's fill and border: translucent in the frosted sheet, solid in the tablet
    // Notification Centre (TABLET2 S1, text on a solid surface).
    property color surface: pal.overlay(0.06)
    property color edge: pal.overlay(0.08)
    radius: 18
    color: surface
    border.width: 1
    border.color: edge

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
        enabled: !!card.entry?.hasDefaultAction
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
                source: card.entry?.applicationIconName || card.entry?.iconName || "preferences-desktop-notification-bell"
            }
            FText {
                Layout.fillWidth: true
                pal: card.pal
                metrics: card.metrics
                text: card.entry?.applicationName || ""
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
                    text: card.relativeTime(card.entry?.created, card.entry?.updated)
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

        RowLayout {
            Layout.fillWidth: true
            spacing: card.metrics.px(10)

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: card.metrics.px(6)

                FText {
                    Layout.fillWidth: true
                    pal: card.pal
                    metrics: card.metrics
                    visible: text.length > 0
                    text: card.entry?.summary || ""
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
                    text: card.bodyParts.text
                    textFormat: Text.StyledText
                    color: card.pal.body
                    linkColor: card.pal.link
                    px: 12.5
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
            // The notification's image (image-data, image-path) or icon, as the stock applet's
            // Icon.qml: Plasma's large icon size, top right, its aspect kept.
            Kirigami.Icon {
                objectName: "notificationImage"
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                Layout.preferredHeight: Kirigami.Units.iconSizes.large
                visible: card.sideImage !== null && valid
                source: card.sideImage
                smooth: true
            }
        }

        // Images in the body (<img src> of local files): below the text, at their own size fitted
        // to the card's width and the preview strip's height.
        Repeater {
            model: card.bodyParts.images
            delegate: Image {
                id: bodyImage
                required property string modelData
                objectName: "bodyImage"
                readonly property real fit: implicitWidth > 0 && implicitHeight > 0
                                            ? Math.min(1, (card.width - 2 * column.anchors.margins) / implicitWidth,
                                                       Kirigami.Units.iconSizes.enormous / implicitHeight) : 0
                Layout.preferredWidth: implicitWidth * fit
                Layout.preferredHeight: implicitHeight * fit
                Layout.maximumWidth: implicitWidth * fit
                Layout.maximumHeight: implicitHeight * fit
                visible: status === Image.Ready
                source: modelData
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                smooth: true
                Accessible.role: Accessible.Graphic
                Accessible.name: i18nc("@info accessible name of an image in a notification", "Image")
            }
        }

        // A file the notification links to (x-kde-urls, a screenshot): its preview, which opens it.
        NotificationThumbnail {
            objectName: "notificationThumbnail"
            Layout.fillWidth: true
            Layout.topMargin: card.metrics.px(2)
            visible: card.urls.length > 0
            pal: card.pal
            metrics: card.metrics
            url: card.urls.length > 0 ? card.urls[0] : ""
            onClicked: card.urlOpened(url)
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
                    width: parent.width * Math.max(0, Math.min(100, card.entry?.percentage || 0)) / 100
                    height: parent.height
                    radius: 3
                    color: card.pal.accentSoft
                }
            }
            FText {
                pal: card.pal
                metrics: card.metrics
                text: i18nc("@info job progress", "%1%", card.entry?.percentage || 0)
                color: card.pal.secondary
                px: 11.5
            }
            TextButton {
                visible: card.jobRunning && !!card.entry?.killable
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
                // The buttons can outlive the card by a moment when the notification list is
                // rebuilt (the sheet opening): their own pal and metrics stay valid, `card` does not.
                delegate: TextButton {
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    pal: card.pal
                    metrics: card.metrics
                    implicitHeight: pal.touch ? Math.max(44, metrics.px(32)) : metrics.px(32)
                    radius: pal.touch ? 12 : 10
                    fontSize: 12.5
                    primary: index === 0 && (card?.primaryAction ?? false)
                    fontWeight: primary ? Font.ExtraBold : Font.Bold
                    text: card ? (card.actionLabels[index] || card.actionNames[index]) : ""
                    onClicked: card?.actionInvoked(card.actionNames[index])
                }
            }
        }
    }
}
