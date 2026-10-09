// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "components"

// Content of the pop-up: the quick settings page (or one of its drill-down
// pages) and, below it, the notification list. The frosted card around it is
// the Plasma style's dialog background drawn by the pop-up window. When the page and the
// notifications together are taller than the screen allows, they scroll together in one
// Flickable (ADAPTIVE 5.3; before, only the list shrank and the rest was cut off).
Item {
    id: content

    required property var backend
    // Colours follow the pop-up window's own colour set (it may differ from the panel's).
    property FusionPalette pal: FusionPalette {
        dark: {
            const c = Kirigami.Theme.backgroundColor;
            return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
        }
        accent: Kirigami.Theme.highlightColor
        accentSoft: Kirigami.Theme.hoverColor
        focus: Kirigami.Theme.focusColor
        link: Kirigami.Theme.linkColor
        fontFamily: Kirigami.Theme.defaultFont.family
        touch: content.touch
        tablet: content.tablet
    }

    // Text scale and pixel grid of the pop-up window (docs/parts/shell-quicksettings.md,
    // "Text scale"): gaps, headers and rows next to text follow it; the card padding does not.
    readonly property alias metrics: fusionMetrics
    readonly property alias scroller: scroller
    FusionMetrics {
        id: fusionMetrics
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
    }

    // Outer size of the card on the board; the window adds the frame padding.
    property real outerWidth: 356
    property real framePaddingLeft: 0
    property real framePaddingRight: 0
    property real framePaddingTop: 0
    property real framePaddingBottom: 0
    // Largest outer height the pop-up may take on this screen.
    property real maxOuterHeight: 820
    property bool open: false
    // Tablet posture and touch sizes (TABLET 4.6, ADAPTIVE 5.3).
    property bool tablet: false
    property bool touch: false

    readonly property real innerLeft: Math.max(0, 16 - framePaddingLeft)
    readonly property real innerRight: Math.max(0, 16 - framePaddingRight)
    readonly property real innerTop: Math.max(0, 16 - framePaddingTop)
    readonly property real innerBottom: Math.max(0, 16 - framePaddingBottom)
    readonly property real maxContentHeight: maxOuterHeight - framePaddingTop - framePaddingBottom

    property Item pageOpener: null
    property double now: Date.now()

    readonly property real contentWidth: outerWidth - framePaddingLeft - framePaddingRight
    implicitWidth: contentWidth
    implicitHeight: Math.min(column.implicitHeight + innerTop + innerBottom, maxContentHeight)
    Layout.minimumWidth: contentWidth
    Layout.maximumWidth: contentWidth
    Layout.preferredWidth: contentWidth
    Layout.minimumHeight: implicitHeight
    Layout.maximumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight

    // Focus moves with the page. The focus ring shows only when the page was opened
    // or closed from the keyboard, not after a click.
    function openPage(name: string, opener: Item) {
        pageOpener = opener;
        const reason = opener && opener.visualFocus ? Qt.TabFocusReason : Qt.OtherFocusReason;
        backend.page = name;
        Qt.callLater(() => {
            const pageItem = subPage.pageItem;
            if (pageItem && pageItem.firstFocusItem) {
                pageItem.firstFocusItem.forceActiveFocus(reason);
            }
        });
    }
    function closePage(fromKeyboard: bool) {
        const pageItem = subPage.pageItem;
        const keyboard = fromKeyboard || !!(pageItem && pageItem.firstFocusItem && pageItem.firstFocusItem.visualFocus);
        backend.page = "main";
        if (pageOpener) {
            const opener = pageOpener;
            Qt.callLater(() => opener.forceActiveFocus(keyboard ? Qt.TabFocusReason : Qt.OtherFocusReason));
        }
        pageOpener = null;
    }
    function focusFirst() {
        const pageItem = subPage.pageItem;
        if (backend.page !== "main" && pageItem && pageItem.firstFocusItem) {
            pageItem.firstFocusItem.forceActiveFocus(Qt.OtherFocusReason);
        } else {
            mainPage.firstFocusItem.forceActiveFocus(Qt.OtherFocusReason);
        }
    }

    Keys.onEscapePressed: event => {
        if (backend.page !== "main") {
            closePage(true);
        } else {
            backend.closeRequested();
        }
        event.accepted = true;
    }

    Timer {
        interval: 30000
        repeat: true
        running: content.open
        triggeredOnStart: true
        onTriggered: content.now = Date.now()
    }

    // Scrolls `item` (inside the column) into view.
    function ensureVisible(item: Item) {
        if (!scroller.interactive || !item) {
            return;
        }
        const top = item.mapToItem(column, 0, 0).y + column.y;
        const bottom = top + item.height;
        if (top < scroller.contentY) {
            scroller.contentY = Math.max(0, top - innerTop);
        } else if (bottom > scroller.contentY + scroller.height) {
            scroller.contentY = Math.min(scroller.contentHeight - scroller.height, bottom - scroller.height + innerBottom);
        }
    }
    onOpenChanged: {
        if (open) {
            scroller.contentY = 0;
        }
    }

    Flickable {
        id: scroller
        objectName: "sheetScroller"
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + content.innerTop + content.innerBottom
        interactive: contentHeight > height + 0.5
        clip: interactive
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            x: content.innerLeft
            y: content.innerTop
            width: content.width - content.innerLeft - content.innerRight
            spacing: content.metrics.px(14)

            // "Notifications | Controls" (tablet posture, notifications on their own sheet): the
            // way back to the Notification Centre without closing (research E-phone 4.2).
            SheetSwitch {
                Layout.alignment: Qt.AlignHCenter
                visible: content.tablet && content.backend.notificationsApart && content.backend.page === "main"
                pal: content.pal
                metrics: content.metrics
                current: 1
                onNotificationsRequested: content.backend.notificationCentreRequested()
            }

            // ---------------------------------------------------------------- pages
            Item {
                id: pageArea
                Layout.fillWidth: true
                readonly property real mainHeight: mainPage.implicitHeight
                readonly property real subHeight: subPage.pageItem ? subPage.pageItem.implicitHeight : 0
                Layout.preferredHeight: content.backend.page === "main" ? mainHeight : Math.max(mainHeight, subHeight)

                QuickSettingsMain {
                    id: mainPage
                    width: parent.width
                    backend: content.backend
                    pal: content.pal
                    metrics: content.metrics
                    visible: content.backend.page === "main"
                    opacity: visible ? 1 : 0
                    Behavior on opacity {
                        enabled: content.pal.motion.animate
                        NumberAnimation { duration: content.pal.motion.toggle }
                    }
                    onOpenPage: (name, opener) => content.openPage(name, opener)
                }

                Loader {
                    id: subPage
                    readonly property var pageItem: item
                    width: parent.width
                    height: parent.height
                    active: content.backend.page !== "main"
                    opacity: status === Loader.Ready ? 1 : 0
                    Behavior on opacity {
                        enabled: content.pal.motion.animate
                        NumberAnimation { duration: content.pal.motion.toggle }
                    }
                    sourceComponent: {
                        switch (content.backend.page) {
                        case "wifi":
                            return wifiComponent;
                        case "bluetooth":
                            return bluetoothComponent;
                        case "audio":
                            return audioComponent;
                        case "power":
                            return powerComponent;
                        case "devices":
                            return devicesComponent;
                        case "display":
                            return displayComponent;
                        default:
                            return null;
                        }
                    }
                }
            }

            // ---------------------------------------------------------------- notifications
            ColumnLayout {
                id: notifications
                Layout.fillWidth: true
                spacing: content.metrics.px(10)
                visible: content.backend.page === "main" && content.backend.notif.available && !content.backend.notificationsApart
                         && (content.backend.notif.count > 0 || content.backend.showEmptyNotifications)

                RowLayout {
                    id: notificationHeader
                    Layout.fillWidth: true
                    Layout.preferredHeight: content.metrics.px(26)
                    Layout.leftMargin: content.metrics.px(4)
                    spacing: content.metrics.px(8)

                    FText {
                        Layout.fillWidth: true
                        pal: content.pal
                        metrics: content.metrics
                        text: i18nc("@title", "Notifications")
                        px: 14
                        font.weight: Font.ExtraBold
                    }
                    TextButton {
                        visible: content.backend.notif.count > 0
                        pal: content.pal
                        metrics: content.metrics
                        radius: height / 2
                        fill: content.pal.clearAllFill
                        textColor: content.pal.controlText
                        implicitHeight: content.metrics.px(26)
                        fontSize: 12
                        text: i18nc("@action:button", "Clear all")
                        onClicked: content.backend.notif.clearAll()
                    }
                }

                FText {
                    Layout.fillWidth: true
                    Layout.preferredHeight: content.metrics.px(44)
                    visible: content.backend.notif.count === 0
                    pal: content.pal
                    metrics: content.metrics
                    horizontalAlignment: Text.AlignHCenter
                    color: content.pal.secondary
                    text: content.backend.dnd.active ? i18nc("@info", "No notifications · Do not disturb is on")
                                                     : i18nc("@info", "No notifications")
                }

                // At its full height: the sheet's Flickable scrolls it with the page.
                ListView {
                    id: notificationList
                    visible: count > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    spacing: content.metrics.px(10)
                    interactive: false
                    model: content.backend.notif.available ? content.backend.notif.model : null

                    delegate: NotificationCard {
                        id: noteCard
                        width: ListView.view.width
                        pal: content.pal
                        metrics: content.metrics
                        now: content.now
                        onFocusInsideChanged: {
                            if (focusInside) {
                                content.ensureVisible(noteCard);
                            }
                        }
                        onActionInvoked: name => {
                            content.backend.notif.invokeAction(index, name, !!model.resident);
                            if (name === "default") {
                                content.backend.closeRequested();
                            }
                        }
                        onCloseClicked: content.backend.notif.close(index)
                        onKillJobClicked: content.backend.notif.killJob(index)
                    }

                    add: Transition {
                        enabled: content.pal.motion.animate
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: content.pal.motion.toggle }
                    }
                    displaced: Transition {
                        enabled: content.pal.motion.animate
                        NumberAnimation { property: "y"; duration: content.pal.motion.toggle; easing.type: content.pal.motion.standardEasing }
                    }
                }
            }
        }
    }

    Component {
        id: wifiComponent
        WifiPage {
            backend: content.backend
            pal: content.pal
            metrics: content.metrics
            onBack: content.closePage(false)
        }
    }
    Component {
        id: bluetoothComponent
        BluetoothPage {
            backend: content.backend
            pal: content.pal
            metrics: content.metrics
            onBack: content.closePage(false)
        }
    }
    Component {
        id: audioComponent
        AudioPage {
            backend: content.backend
            initialTab: content.backend.audioPage === "input" ? 1 : 0
            pal: content.pal
            metrics: content.metrics
            onBack: content.closePage(false)
        }
    }
    Component {
        id: devicesComponent
        DevicesPage {
            backend: content.backend
            pal: content.pal
            metrics: content.metrics
            onBack: content.closePage(false)
        }
    }
    Component {
        id: displayComponent
        DisplayPage {
            backend: content.backend
            pal: content.pal
            metrics: content.metrics
            onBack: content.closePage(false)
        }
    }
    Component {
        id: powerComponent
        PowerPage {
            backend: content.backend
            pal: content.pal
            metrics: content.metrics
            onBack: content.closePage(false)
        }
    }
}
