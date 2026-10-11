// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "components"
import "components/Icons.js" as Icons
import "../code/notifications.js" as Notes

// One notification of the list (Quick Settings board, notification cards):
// app icon and name (in an app's group: the summary, the group header names the app), time,
// summary, body, the notification's image, file thumbnail, job progress
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
    // An inline reply was sent.
    signal replied(string text)
    // A file job: pause or resume it; open its destination folder (`highlight`: show the one file
    // selected in it).
    signal suspendJobClicked()
    signal resumeJobClicked()
    signal folderRequested(string url, bool highlight)
    // The app's notification settings.
    signal configureClicked()

    // The row's data. While a removed row's card is torn down, `model` and this property read as
    // null, so every use is optional (`entry?.`).
    readonly property var entry: model || ({})
    // org.kde.notificationmanager Notifications enums
    // One of an app's notifications under its group header (NotificationEntry.qml).
    readonly property bool inGroup: !!entry?.isInGroup
    readonly property bool isJob: entry?.type === 2
    readonly property bool jobRunning: isJob && entry?.jobState !== 0
    // "running", "paused", "failed", "finished" or "" (contents/code/notifications.js).
    readonly property string jobState: Notes.jobState(entry?.type, entry?.jobState, entry?.jobError)
    readonly property var jobDetails: entry?.jobDetails ?? null
    // A finished file job's Open and Open Containing Folder (the stock applet's JobItem).
    readonly property var fileActions: Notes.fileActions(jobState, jobDetails ? Number(jobDetails.totalFiles) : 0,
                                                         jobDetails ? String(jobDetails.effectiveDestUrl) : "")
    // The summary as the stock applet's Summary.qml words it: a job's state after its name, and
    // nothing when an app sends its own name as the summary.
    readonly property string summaryText: {
        const summary = entry?.summary || "";
        switch (jobState) {
        case "paused":
            return summary ? i18nc("Job name, e.g. Copying is paused", "%1 (Paused)", summary) : "";
        case "failed":
            return summary ? i18nc("Job name, e.g. Copying has failed", "%1 (Failed)", summary) : i18n("Job Failed");
        case "finished":
            return summary ? i18nc("Job name, e.g. Copying has finished", "%1 (Finished)", summary) : i18n("Job Finished");
        default:
            return Notes.summaryShown(summary, entry?.applicationName) ? summary : "";
        }
    }
    readonly property var actionNames: entry?.actionNames || []
    readonly property var actionLabels: entry?.actionLabels || []
    readonly property bool primaryAction: entry?.urgency === 4 || entry?.timeout === 0
    // The body's text and the images it carries (contents/code/notifications.js).
    readonly property var bodyParts: Notes.splitBody(entry?.body)
    readonly property var sideImage: Notes.sideImage(entry?.image, entry?.iconName, entry?.applicationIconName)
    readonly property var urls: entry?.urls || []
    readonly property string bodyText: bodyParts.text
    // Inline reply (the stock applet's ActionContainer): "button" puts a Reply button first among
    // the actions, which opens the field; "field" shows the field at once (replying is the only
    // action); "none".
    readonly property string replyMode: Notes.replyMode(!!entry?.hasReplyAction, actionNames.length)
    property bool replying: false
    readonly property bool replyShown: replyMode === "field" || (replyMode === "button" && replying)
    function beginReply() {
        replying = true;
        replyField.forceActiveFocus(Qt.TabFocusReason);
    }
    function sendReply() {
        if (replyField.text.length > 0) {
            card.replied(replyField.text);
            replyField.text = "";
            replying = false;
        }
    }
    readonly property bool hovered: cardHover.hovered
    readonly property bool closable: !jobRunning && entry?.closable !== false
    // The header's buttons show on hover, keyboard focus and in touch mode.
    readonly property bool buttonsShown: pal.touch || hovered || closeButton.activeFocus || configureButton.activeFocus
    readonly property bool showClose: closable && buttonsShown
    readonly property bool configurable: !inGroup && !!entry?.configurable
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
                visible: !card.inGroup
                source: card.entry?.applicationIconName || card.entry?.iconName || "preferences-desktop-notification-bell"
            }
            // The app's name; in a group (whose header names the app) the summary takes its place.
            FText {
                objectName: "headerText"
                Layout.fillWidth: true
                pal: card.pal
                metrics: card.metrics
                text: card.inGroup ? card.summaryText : (card.entry?.applicationName || "")
                color: card.inGroup ? card.pal.text : card.pal.secondary
                px: card.inGroup ? 13.5 : 11.5
                font.weight: Font.ExtraBold
            }
            // Time, replaced by the Configure and close buttons on hover or keyboard focus (in
            // touch mode all are shown). The buttons stay in the tab chain (transparent), so
            // keyboard users can reach them too.
            Item {
                Layout.preferredWidth: card.pal.touch ? timeLabel.implicitWidth + card.metrics.px(4) + headerButtons.implicitWidth
                                                      : card.buttonsShown ? headerButtons.implicitWidth : timeLabel.implicitWidth
                Layout.preferredHeight: card.metrics.px(22)

                FText {
                    id: timeLabel
                    anchors.right: card.pal.touch ? headerButtons.left : parent.right
                    anchors.rightMargin: card.pal.touch ? card.metrics.px(4) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    visible: card.pal.touch || !card.buttonsShown
                    pal: card.pal
                    metrics: card.metrics
                    text: card.relativeTime(card.entry?.created, card.entry?.updated)
                    color: card.pal.tertiary
                    px: 11.5
                }
                Row {
                    id: headerButtons
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: card.metrics.px(4)
                    opacity: card.buttonsShown ? 1 : 0

                    // The app's notification settings (the stock applet's Configure button; in a
                    // group the header has it).
                    IconButton {
                        id: configureButton
                        objectName: "configureButton"
                        visible: card.configurable
                        pal: card.pal
                        size: card.pal.touch ? 32 : 22
                        iconSize: card.pal.touch ? 14 : 12
                        fill: "transparent"
                        iconPath: Icons.settingsSmall
                        text: card.entry?.configureActionLabel || i18nc("@action:button notification settings of an app", "Configure")
                        Accessible.description: card.entry?.applicationName || ""
                        toolTip: card.buttonsShown ? text : ""
                        onClicked: card.configureClicked()
                    }
                    IconButton {
                        id: closeButton
                        objectName: "closeButton"
                        enabled: card.closable
                        opacity: card.closable ? 1 : 0
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
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: card.metrics.px(10)

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: card.metrics.px(6)

                FText {
                    objectName: "summary"
                    Layout.fillWidth: true
                    pal: card.pal
                    metrics: card.metrics
                    visible: text.length > 0 && !card.inGroup
                    text: card.summaryText
                    px: 13.5
                    font.weight: Font.ExtraBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                }
                // Also for jobs: "file.txt to Downloads" with a link, or why it failed.
                FText {
                    objectName: "body"
                    Layout.fillWidth: true
                    pal: card.pal
                    metrics: card.metrics
                    visible: text.length > 0
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

        // Job progress (file copies and downloads) while it runs or is paused, with Pause/Resume
        // and Cancel where the job offers them.
        RowLayout {
            objectName: "jobProgress"
            Layout.fillWidth: true
            Layout.topMargin: card.metrics.px(2)
            visible: card.jobState === "running" || card.jobState === "paused"
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
                objectName: "jobPause"
                visible: !!card.entry?.suspendable
                pal: card.pal
                metrics: card.metrics
                fontSize: 12
                text: card.jobState === "paused" ? i18nc("@action:button resume a paused file transfer", "Resume")
                                                 : i18nc("@action:button pause a file transfer", "Pause")
                onClicked: card.jobState === "paused" ? card.resumeJobClicked() : card.suspendJobClicked()
            }
            TextButton {
                objectName: "jobCancel"
                visible: card.jobRunning && !!card.entry?.killable
                pal: card.pal
                metrics: card.metrics
                fontSize: 12
                text: i18nc("@action:button cancel a file transfer", "Cancel")
                onClicked: card.killJobClicked()
            }
        }

        // A finished file job: open the file, or its folder (Popups board: Open, Show in folder).
        RowLayout {
            objectName: "jobFiles"
            Layout.fillWidth: true
            Layout.topMargin: card.metrics.px(6)
            visible: card.fileActions.folder
            spacing: card.metrics.px(8)

            TextButton {
                objectName: "jobOpen"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                visible: card.fileActions.open
                pal: card.pal
                metrics: card.metrics
                implicitHeight: pal.touch ? Math.max(44, metrics.px(32)) : metrics.px(32)
                radius: pal.touch ? 12 : 10
                fontSize: 12.5
                primary: true
                fontWeight: Font.ExtraBold
                text: i18nc("@action:button open the copied file", "Open")
                onClicked: card.urlOpened(card.fileActions.folderUrl)
            }
            TextButton {
                objectName: "jobFolder"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                pal: card.pal
                metrics: card.metrics
                implicitHeight: pal.touch ? Math.max(44, metrics.px(32)) : metrics.px(32)
                radius: pal.touch ? 12 : 10
                fontSize: 12.5
                text: i18nc("@action:button", "Open Containing Folder")
                onClicked: card.folderRequested(card.fileActions.folderUrl, card.fileActions.highlight)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: card.metrics.px(6)
            visible: !card.isJob && card.actionNames.length > 0 && !card.replyShown
            spacing: card.metrics.px(8)

            // "Reply" first, as in the stock applet; it opens the reply field.
            TextButton {
                objectName: "replyButton"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                visible: card.replyMode === "button"
                pal: card.pal
                metrics: card.metrics
                implicitHeight: pal.touch ? Math.max(44, metrics.px(32)) : metrics.px(32)
                radius: pal.touch ? 12 : 10
                fontSize: 12.5
                text: card.entry?.replyActionLabel || i18nc("@action:button reply to a message", "Reply")
                onClicked: card.beginReply()
            }
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

        // The inline reply: the app's placeholder and button text when it gives them. Return
        // sends, Escape goes back to the actions (when there are any).
        RowLayout {
            objectName: "replyRow"
            Layout.fillWidth: true
            Layout.topMargin: card.metrics.px(6)
            visible: card.replyShown
            spacing: card.metrics.px(8)

            QQC2.TextField {
                id: replyField
                objectName: "replyField"
                Layout.fillWidth: true
                Layout.preferredHeight: card.pal.touch ? Math.max(44, card.metrics.px(32)) : card.metrics.px(32)
                placeholderText: card.entry?.replyPlaceholderText || i18nc("@info:placeholder", "Type a reply…")
                Accessible.name: placeholderText
                onAccepted: card.sendReply()
                Keys.onEscapePressed: event => {
                    if (card.replyMode === "button" && card.replying) {
                        card.replying = false;
                        text = "";
                        event.accepted = true;
                    } else {
                        event.accepted = false;
                    }
                }
            }
            TextButton {
                objectName: "replySend"
                pal: card.pal
                metrics: card.metrics
                implicitHeight: pal.touch ? Math.max(44, metrics.px(32)) : metrics.px(32)
                radius: pal.touch ? 12 : 10
                fontSize: 12.5
                primary: true
                enabled: replyField.text.length > 0
                text: card.entry?.replySubmitButtonText || i18nc("@action:button send a reply", "Send")
                onClicked: card.sendReply()
            }
        }
    }
}
