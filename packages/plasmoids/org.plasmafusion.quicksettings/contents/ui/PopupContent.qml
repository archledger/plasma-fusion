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
    // The item of the subpage shown: the clipboard's kept page or the disposable loader's item.
    readonly property var pageItem: content.backend.page === "clipboard" ? clipboardPage.item : subPage.pageItem
    // The pages follow backend.page: from the Connections below and once at completion. A subpage
    // can be requested before this content is created (this loader is asynchronous - a Meta+V
    // during the first seconds after login), and that first change would otherwise be missed
    // (review 4253399257). The clipboard page lives in its own loader, kept once opened, so that
    // visiting another subpage cannot destroy it (review 4253488183), and it is reset
    // synchronously here - before the popup's own focusFirst() pass against a stale editor or QR
    // view (review 4253488189).
    function syncPage(): void {
        const name = content.backend.page;
        if (name === "clipboard") {
            if (!clipboardPage.active) {
                clipboardPage.active = true; // creates the kept page once (synchronously)
            }
            if (clipboardPage.item) {
                clipboardPage.item.reset();
            }
            if (subPage.wantedComponent !== null) {
                subPage.wantedComponent = null;
            }
        } else if (name === "main") {
            if (subPage.wantedComponent !== null) {
                subPage.wantedComponent = null;
            }
        } else {
            const wanted = subPage.componentFor(name);
            if (wanted !== subPage.wantedComponent) {
                subPage.wantedComponent = wanted;
            }
        }
    }
    Component.onCompleted: syncPage()
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
        backend.pageDirect = false;
        backend.page = name;
        Qt.callLater(() => {
            const pageItem = content.pageItem;
            if (pageItem && pageItem.firstFocusItem) {
                pageItem.firstFocusItem.forceActiveFocus(reason);
            }
        });
    }
    function closePage(fromKeyboard: bool) {
        const pageItem = content.pageItem;
        const keyboard = fromKeyboard || !!(pageItem && pageItem.firstFocusItem && pageItem.firstFocusItem.visualFocus);
        backend.page = "main";
        backend.pageDirect = false;
        // A page opened on its own has no opener: the focus goes to the top of quick settings.
        const opener = pageOpener || mainPage.firstFocusItem;
        Qt.callLater(() => opener.forceActiveFocus(keyboard ? Qt.TabFocusReason : Qt.OtherFocusReason));
        pageOpener = null;
    }
    function focusFirst() {
        const pageItem = content.pageItem;
        if (backend.page !== "main" && pageItem && pageItem.firstFocusItem) {
            pageItem.firstFocusItem.forceActiveFocus(Qt.OtherFocusReason);
        } else {
            mainPage.firstFocusItem.forceActiveFocus(Qt.OtherFocusReason);
        }
    }

    // A page opened on its own (the clipboard sheet from its button or Meta+V) closes the sheet.
    Keys.onEscapePressed: event => {
        if (backend.page !== "main" && !backend.pageDirect) {
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
                readonly property real subHeight: content.pageItem ? content.pageItem.implicitHeight : 0
                // The clipboard sheet takes its own height (it opens on its own, and its list fits
                // the screen); the other pages keep at least the quick settings' height.
                Layout.preferredHeight: content.backend.page === "main" ? mainHeight
                                      : content.backend.page === "clipboard" ? subHeight : Math.max(mainHeight, subHeight)

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

                // The clipboard page is kept for the process in its own loader: constructing it
                // dominated the clipboard sheet's open time (160-216 ms measured against the
                // main sheet's 8-35; survey 4, 2026-10-12) and, kept, its height is known before
                // the window maps, so the sheet does not resize after its first frame. Its own
                // loader keeps the page alive even when another subpage is visited in between
                // (review 4253488183).
                Loader {
                    id: clipboardPage
                    width: parent.width
                    height: parent.height
                    active: false
                    visible: content.backend.page === "clipboard"
                    opacity: status === Loader.Ready ? 1 : 0
                    Behavior on opacity {
                        enabled: content.pal.motion.animate
                        NumberAnimation { duration: content.pal.motion.toggle }
                    }
                    sourceComponent: clipboardComponent
                }
                Loader {
                    id: subPage
                    readonly property var pageItem: item
                    width: parent.width
                    height: parent.height
                    // Every other page keeps the old behavior (destroyed when it is left).
                    property var wantedComponent: null
                    active: wantedComponent !== null
                    visible: content.backend.page !== "main" && content.backend.page !== "clipboard"
                    opacity: status === Loader.Ready ? 1 : 0
                    Behavior on opacity {
                        enabled: content.pal.motion.animate
                        NumberAnimation { duration: content.pal.motion.toggle }
                    }
                    sourceComponent: wantedComponent

                    function componentFor(name) {
                        switch (name) {
                        case "wifi":
                            return wifiComponent;
                        case "bluetooth":
                            return bluetoothComponent;
                        case "audio":
                            return audioComponent;
                        case "power":
                            return powerComponent;
                        case "profiles":
                            return profilesComponent;
                        case "devices":
                            return devicesComponent;
                        case "display":
                            return displayComponent;
                        default:
                            return null;
                        }
                    }
                }
                Connections {
                    target: content.backend
                    function onPageChanged() {
                        content.syncPage();
                    }
                }
            }

            // ---------------------------------------------------------------- notifications
            ColumnLayout {
                id: notifications
                Layout.fillWidth: true
                spacing: content.metrics.px(10)
                visible: content.backend.notif.listShown

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

                // At its full height: the sheet's Flickable scrolls it with the page. A Column of rows
                // (NotificationList.qml says why not a ListView).
                NotificationList {
                    id: notificationList
                    visible: count > 0
                    Layout.fillWidth: true
                    spacing: content.metrics.px(10)
                    notif: content.backend.notif
                    pal: content.pal
                    metrics: content.metrics
                    motion: content.pal.motion
                    now: content.now
                    onEntryFocused: entry => content.ensureVisible(entry)
                    onDone: content.backend.closeRequested()
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
        id: profilesComponent
        ProfilesPage {
            backend: content.backend
            pal: content.pal
            metrics: content.metrics
            onBack: content.closePage(false)
        }
    }
    Component {
        id: clipboardComponent
        ClipboardPage {
            backend: content.backend
            pal: content.pal
            metrics: content.metrics
            maxHeight: content.maxContentHeight - content.innerTop - content.innerBottom
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
