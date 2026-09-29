// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "components"

// Content of the pop-up: the quick settings page (or one of its drill-down
// pages) and, below it, the notification list. The frosted card around it is
// the Plasma style's dialog background drawn by the pop-up window.
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

    ColumnLayout {
        id: column
        x: content.innerLeft
        y: content.innerTop
        width: content.width - content.innerLeft - content.innerRight
        spacing: 14

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
                visible: content.backend.page === "main"
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                onOpenPage: (name, opener) => content.openPage(name, opener)
            }

            Loader {
                id: subPage
                readonly property var pageItem: item
                width: parent.width
                height: parent.height
                active: content.backend.page !== "main"
                opacity: status === Loader.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                sourceComponent: {
                    switch (content.backend.page) {
                    case "wifi":
                        return wifiComponent;
                    case "bluetooth":
                        return bluetoothComponent;
                    case "audio":
                        return audioComponent;
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
            spacing: 10
            visible: content.backend.page === "main" && content.backend.notif.available
                     && (content.backend.notif.count > 0 || content.backend.showEmptyNotifications)

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                Layout.leftMargin: 4
                spacing: 8

                FText {
                    Layout.fillWidth: true
                    pal: content.pal
                    text: i18nc("@title", "Notifications")
                    px: 14
                    font.weight: Font.ExtraBold
                }
                TextButton {
                    visible: content.backend.notif.count > 0
                    pal: content.pal
                    implicitHeight: 26
                    radius: 13
                    fill: content.pal.clearAllFill
                    textColor: content.pal.controlText
                    fontSize: 12
                    text: i18nc("@action:button", "Clear all")
                    onClicked: content.backend.notif.clearAll()
                }
            }

            FText {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                visible: content.backend.notif.count === 0
                pal: content.pal
                horizontalAlignment: Text.AlignHCenter
                color: content.pal.secondary
                text: content.backend.dnd.active ? i18nc("@info", "No notifications · Do not disturb is on")
                                                 : i18nc("@info", "No notifications")
            }

            ListView {
                id: notificationList
                visible: count > 0
                Layout.fillWidth: true
                readonly property real available: content.maxContentHeight - content.innerTop - content.innerBottom
                                                  - pageArea.Layout.preferredHeight - 14 - 26 - 10
                Layout.preferredHeight: Math.min(contentHeight, Math.max(140, available))
                clip: true
                spacing: 10
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                model: content.backend.notif.available ? content.backend.notif.model : null

                delegate: NotificationCard {
                    width: ListView.view.width
                    pal: content.pal
                    now: content.now
                    onFocusInsideChanged: {
                        if (focusInside) {
                            notificationList.positionViewAtIndex(index, ListView.Contain);
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
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 }
                }
                displaced: Transition {
                    NumberAnimation { property: "y"; duration: 180; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    Component {
        id: wifiComponent
        WifiPage {
            backend: content.backend
            pal: content.pal
            onBack: content.closePage(false)
        }
    }
    Component {
        id: bluetoothComponent
        BluetoothPage {
            backend: content.backend
            pal: content.pal
            onBack: content.closePage(false)
        }
    }
    Component {
        id: audioComponent
        AudioPage {
            backend: content.backend
            pal: content.pal
            onBack: content.closePage(false)
        }
    }
}
