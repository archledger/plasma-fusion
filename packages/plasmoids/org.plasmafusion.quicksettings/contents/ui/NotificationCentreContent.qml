// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasma5support as P5Support
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.plasma.extras as PlasmaExtras
import "components"
import "../code/notifications.js" as Notes

// The Notification Centre in tablet posture (TABLET2 S1): the notification history on its own
// full-screen sheet under the top bar, apart from the controls (the quick-settings sheet), as on
// iPadOS and Android tablets. Research round 2: never a narrow centred column in landscape, so the
// clock, the date and Do Not Disturb take a column on the left and the list the rest (portrait: one
// column with the clock above); the cards are solid behind their text (E-phone 4.2 MUST); newest
// first; "Clear all" stays visible and can be undone for 5 s; a card is dismissed by a sideways
// swipe (NotificationCard); the history is grouped by app as in the laptop sheet and the stock
// applet (NotificationEntry.qml): a group lists two notifications, the rest drawn as a stack under
// them until "Show N More" opens it; a long press on a card offers "No pop-ups from <app>" and its
// notification settings (E-phone 4.3). A tap on empty space, a swipe up, Escape or an action closes
// it; a sideways swipe on empty space, or the segment at the top, switches to the controls.
FocusScope {
    id: centre

    required property var backend
    required property FusionMetrics metrics
    required property Motion motion
    // Height of the top bar (the sheet starts under it), the wallpaper's screen, the open state.
    property real topBar: 44
    property int screenNumber: 0
    property string glass: "full"
    property real progress: 0
    property bool shown: false

    signal closeRequested()
    signal controlsRequested()
    signal menuClosed()
    readonly property bool menuOpen: cardMenu.status === PlasmaExtras.Menu.Open

    readonly property var pal: backend.pal
    readonly property var notif: backend.notif
    readonly property bool landscape: width >= height && width >= 960
    readonly property real margin: landscape ? 40 : 24
    readonly property real sideWidth: landscape ? Math.min(400, Math.round(width * 0.28)) : 0
    readonly property real listX: landscape ? margin + sideWidth + 40 : Math.round((width - listWidth) / 2)
    readonly property real listWidth: landscape ? Math.min(760, width - margin - sideWidth - 40 - margin)
                                                : Math.min(640, width - 2 * margin)
    // Solid card surface (E-phone 4.2): the sheet colours of the quick settings, opaque.
    readonly property color cardSurface: pal.dark ? "#1b2031" : "#ffffff"
    readonly property color cardEdge: pal.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.10)
    property double now: Date.now()
    property real dragY: 0

    Accessible.role: Accessible.Pane
    Accessible.name: i18nc("@title accessible name of the tablet notification centre", "Notifications")

    // ---- Clear all, with undo: the list is hidden for 5 s and cleared then (or when the sheet
    // closes); Undo shows it again.
    property bool pendingClear: false
    function clearAll(): void {
        pendingClear = true;
        clearTimer.restart();
    }
    function undoClear(): void {
        clearTimer.stop();
        pendingClear = false;
    }
    function commitClear(): void {
        if (pendingClear) {
            clearTimer.stop();
            notif.clearAll();
            pendingClear = false;
        }
    }
    Timer {
        id: clearTimer
        interval: 5000
        onTriggered: centre.commitClear()
    }
    onShownChanged: {
        if (!shown) {
            commitClear();
            collapsed();
        } else {
            now = Date.now();
        }
        animateTo(shown ? 1 : 0);
    }
    Component.onCompleted: {
        if (shown) {
            animateTo(1);
        }
    }
    // Opens in popupIn (200 ms, decelerating), closes in popupOut; snapClosed() when the window
    // went away (another window became active).
    function animateTo(value: real): void {
        progressAnimation.stop();
        progressAnimation.to = value;
        progressAnimation.duration = value > 0 ? motion.popupIn : motion.popupOut;
        progressAnimation.easing.type = value > 0 ? Easing.OutCubic : Easing.InCubic;
        progressAnimation.start();
    }
    function snapClosed(): void {
        progressAnimation.stop();
        progress = 0;
    }
    NumberAnimation {
        id: progressAnimation
        target: centre
        property: "progress"
        duration: centre.motion.popupIn
    }

    // ---- Groups: the history is grouped by app (NotificationEntry.qml); groups opened while the
    // sheet is shown close with it.
    function collapsed(): void {
        notif.collapseAllGroups();
    }
    Timer {
        // relative times ("5 min ago") while the sheet is open
        interval: 30000
        repeat: true
        running: centre.shown
        onTriggered: centre.now = Date.now()
    }

    // ---- Per-app pop-ups and history (Plasma's own settings, plasmanotifyrc
    // [Applications][<desktop entry>] ShowPopups and ShowInHistory, the ones the notification
    // settings page writes; research E-phone 4.3: control reachable from the notification itself).
    // Turning one back on removes the key (Plasma's default: on).
    function setAppKey(desktopEntry: string, key: string, on: bool): void {
        if (!/^[A-Za-z0-9._-]+$/.test(desktopEntry)) {
            return;
        }
        backend.run("kwriteconfig6 --file plasmanotifyrc --group Applications --group " + desktopEntry
                    + " --key " + key + (on ? " --delete" : " --type bool false") + " --notify");
        console.info("quicksettings: notifications from " + desktopEntry + ": " + key + " " + (on ? "on" : "off"));
    }
    property int menuRow: -1
    property string menuEntry: ""
    property string menuApp: ""
    property bool menuPopupsOn: true
    property bool menuHistoryOn: true
    property point menuAt: Qt.point(0, 0)
    // Reads the app's two settings, then opens the menu with the matching actions.
    function openCardMenu(): void {
        if (!/^[A-Za-z0-9._-]+$/.test(menuEntry)) {
            menuPopupsOn = true;
            menuHistoryOn = true;
            cardMenu.open(menuAt.x, menuAt.y);
            return;
        }
        const read = "kreadconfig6 --file plasmanotifyrc --group Applications --group " + menuEntry + " --key ";
        settingsReader.connectSource(read + "ShowPopups --default true; " + read + "ShowInHistory --default true # " + Date.now());
    }
    P5Support.DataSource {
        id: settingsReader
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            const lines = String(data["stdout"] || "").trim().split("\n");
            centre.menuPopupsOn = lines[0] !== "false";
            centre.menuHistoryOn = lines.length < 2 || lines[1] !== "false";
            cardMenu.open(centre.menuAt.x, centre.menuAt.y);
        }
    }
    PlasmaExtras.Menu {
        id: cardMenu
        placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
        onStatusChanged: {
            if (status === PlasmaExtras.Menu.Closed) {
                centre.menuClosed();
            }
        }
        PlasmaExtras.MenuItem {
            text: centre.menuPopupsOn ? i18nc("@action:inmenu %1 application name", "No Pop-ups from %1", centre.menuApp)
                                      : i18nc("@action:inmenu %1 application name", "Show Pop-ups from %1", centre.menuApp)
            icon: centre.menuPopupsOn ? "notifications-disabled" : "notifications"
            visible: centre.menuEntry !== ""
            onClicked: centre.setAppKey(centre.menuEntry, "ShowPopups", !centre.menuPopupsOn)
        }
        PlasmaExtras.MenuItem {
            text: centre.menuHistoryOn ? i18nc("@action:inmenu %1 application name", "Don't Keep Notifications from %1", centre.menuApp)
                                       : i18nc("@action:inmenu %1 application name", "Keep Notifications from %1", centre.menuApp)
            icon: centre.menuHistoryOn ? "edit-clear-history" : "view-history"
            visible: centre.menuEntry !== ""
            onClicked: centre.setAppKey(centre.menuEntry, "ShowInHistory", !centre.menuHistoryOn)
        }
        PlasmaExtras.MenuItem {
            text: i18nc("@action:inmenu", "Notification Settings…")
            icon: "configure"
            onClicked: {
                centre.notif.configure(centre.menuRow);
                centre.closeRequested();
            }
        }
    }

    Keys.onEscapePressed: closeRequested()

    // ---- Backdrop: the Tinted material (the wallpaper's static blurred copy); a tap on empty space
    // closes.
    FusionBackdrop {
        anchors.fill: parent
        followWallpaper: true
        screenNumber: centre.screenNumber
        dark: centre.pal.dark
        glass: centre.glass
        opacity: centre.progress * (1 - Math.min(1, centre.dragY / 400))
    }
    TapHandler {
        onTapped: centre.closeRequested()
    }
    // A swipe up closes, a sideways swipe switches to the controls: on the zones outside the list
    // (the clock column, the strip above the list, the right margin), so a card keeps its own
    // sideways swipe and the list its scrolling.
    component SwipeZone: Item {
        DragHandler {
            acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Stylus
            target: null
            dragThreshold: 16
            onTranslationChanged: {
                if (active) {
                    centre.dragY = Math.max(0, -translation.y);
                }
            }
            onActiveChanged: {
                if (active) {
                    return;
                }
                const dx = centroid.position.x - centroid.pressPosition.x;
                const dy = centroid.position.y - centroid.pressPosition.y;
                if (Math.abs(dx) > 96 && Math.abs(dx) > 2 * Math.abs(dy)) {
                    centre.controlsRequested();
                } else if (-dy >= 96 || centroid.velocity.y <= -800) {
                    centre.closeRequested();
                }
                dragBack.start();
            }
        }
    }
    SwipeZone {
        // left of the list (the clock column in landscape)
        width: Math.max(0, centre.listX - 16)
        height: parent.height
    }
    SwipeZone {
        // right of the list
        x: centre.listX + centre.listWidth + 16
        width: Math.max(0, parent.width - x)
        height: parent.height
    }
    SwipeZone {
        // above the list: the top bar's edge, the segment and the header row
        x: centre.listX - 16
        width: centre.listWidth + 32
        height: centre.topBar + listColumn.y + 56
    }
    NumberAnimation {
        id: dragBack
        target: centre
        property: "dragY"
        to: 0
        duration: centre.motion.popupOut
        easing.type: centre.motion.standardEasing
    }

    Item {
        id: body
        width: parent.width
        height: parent.height - centre.topBar
        y: centre.topBar - 24 * (1 - centre.progress) - Math.min(160, centre.dragY * 0.5)
        opacity: Math.min(1, centre.progress * 1.4) * (1 - Math.min(1, centre.dragY / 300))

        // ---- Segment: Notifications | Controls (the two sheets, E-phone 4.2 sideways switch)
        SheetSwitch {
            id: segment
            anchors.horizontalCenter: parent.horizontalCenter
            y: 16
            pal: centre.pal
            metrics: centre.metrics
            edge: centre.cardEdge
            current: 0
            onControlsRequested: centre.controlsRequested()
        }

        // ---- The clock column (landscape) or header (portrait)
        Column {
            id: side
            x: centre.landscape ? centre.margin : centre.listX
            y: centre.landscape ? 88 : 76
            width: centre.landscape ? centre.sideWidth : centre.listWidth
            spacing: 6
            Text {
                text: Qt.formatTime(new Date(centre.now), Qt.locale().timeFormat(Locale.ShortFormat))
                color: centre.pal.text
                font.pixelSize: centre.metrics.font(centre.landscape ? 64 : 44)
                font.weight: Font.Light
                textFormat: Text.PlainText
            }
            Text {
                width: parent.width
                // The region's long date without the year ("Sunday, October 11" in en_US).
                text: Qt.formatDate(new Date(centre.now), Notes.centreDateFormat(Qt.locale().dateFormat(Locale.LongFormat)))
                color: centre.pal.text
                font.pixelSize: centre.metrics.font(centre.landscape ? 20 : 17)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Item {
                width: 1
                height: 10
                visible: dndChip.visible
            }
            // Do Not Disturb: shown while it is on; a tap turns it off.
            PillButton {
                id: dndChip
                visible: centre.backend.dnd.active
                text: centre.backend.dnd.untilText !== ""
                      ? i18nc("@action:button %1 time", "Do not disturb until %1 · Turn off", centre.backend.dnd.untilText)
                      : i18nc("@action:button", "Do not disturb · Turn off")
                onClicked: centre.backend.dnd.toggle()
            }
            // Why it is on, besides a time: the apps that hold it (stock wording).
            Text {
                width: parent.width
                visible: dndChip.visible && text !== ""
                text: centre.backend.dnd.reasons.join(" · ")
                color: centre.pal.secondary
                font.pixelSize: centre.metrics.font(14)
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
        }

        // ---- The list column
        Item {
            id: listColumn
            x: centre.listX
            y: centre.landscape ? 76 : side.y + side.height + 20
            width: centre.listWidth
            height: body.height - y - 16

            RowLayout {
                id: header
                width: parent.width
                height: 56
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: i18nc("@title", "Notifications")
                    color: centre.pal.text
                    font.pixelSize: centre.metrics.font(20)
                    font.weight: Font.ExtraBold
                    textFormat: Text.PlainText
                }
                // "Clear all": a 56 px target in the sheet's corner (E-phone 4.2).
                PillButton {
                    id: clearButton
                    visible: centre.notif.count > 0 && !centre.pendingClear
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: 44
                    text: i18nc("@action:button", "Clear all")
                    onClicked: centre.clearAll()
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: header.height + 48
                visible: centre.notif.count === 0 && !centre.pendingClear
                text: centre.backend.dnd.active ? i18nc("@info", "No notifications · Do not disturb is on")
                                                : i18nc("@info", "No notifications")
                color: centre.pal.secondary
                font.pixelSize: centre.metrics.font(15)
                textFormat: Text.PlainText
            }

            ListView {
                id: list
                objectName: "notificationCentreList"
                y: header.height + 8
                width: parent.width
                height: parent.height - y
                clip: true
                visible: !centre.pendingClear
                boundsBehavior: Flickable.StopAtBounds
                model: centre.notif.available ? centre.notif.model : null
                Accessible.role: Accessible.List
                Accessible.name: i18nc("@title", "Notifications")

                spacing: 12
                delegate: NotificationEntry {
                    width: ListView.view.width
                    pal: centre.pal
                    metrics: centre.metrics
                    notif: centre.notif
                    now: centre.now
                    surface: centre.cardSurface
                    edge: centre.cardEdge
                    stackEdges: true
                    menus: true
                    onDone: centre.closeRequested()
                    onMenuRequested: (card, at) => {
                        centre.menuRow = index;
                        centre.menuEntry = String(model.desktopEntry || "");
                        centre.menuApp = String(model.applicationName || "");
                        cardMenu.visualParent = card;
                        centre.menuAt = at;
                        centre.openCardMenu();
                    }
                }

                displaced: Transition {
                    enabled: centre.motion.animate
                    NumberAnimation { property: "y"; duration: centre.motion.toggle; easing.type: centre.motion.standardEasing }
                }
            }

            // Undo for "Clear all".
            Rectangle {
                id: undoBar
                visible: centre.pendingClear
                anchors.horizontalCenter: parent.horizontalCenter
                y: header.height + 96
                width: undoRow.implicitWidth + 32
                height: 56
                radius: 28
                color: centre.cardSurface
                border.width: 1
                border.color: centre.cardEdge
                Accessible.role: Accessible.AlertMessage
                Accessible.name: i18nc("@info", "Notifications cleared")
                // takes presses beside the button, so the backdrop does not close the sheet
                MouseArea {
                    anchors.fill: parent
                }
                RowLayout {
                    id: undoRow
                    anchors.centerIn: parent
                    spacing: 16
                    Text {
                        text: i18nc("@info", "Notifications cleared")
                        color: centre.pal.text
                        font.pixelSize: centre.metrics.font(14)
                        textFormat: Text.PlainText
                    }
                    PillButton {
                        Layout.preferredHeight: 44
                        accent: true
                        text: i18nc("@action:button", "Undo")
                        onClicked: centre.undoClear()
                    }
                }
            }
        }
    }

    // A 44 px pill (solid, or translucent over the backdrop; accent for the undo action). An
    // AbstractButton takes the press, so the backdrop's tap-to-close does not fire with it.
    component PillButton: T.AbstractButton {
        id: pill
        property bool translucent: false
        property bool accent: false
        implicitWidth: label.implicitWidth + 36
        implicitHeight: 44
        Accessible.role: Accessible.Button
        Accessible.name: text
        contentItem: Text {
            id: label
            text: pill.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: centre.pal.text
            font.pixelSize: centre.metrics.font(14)
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
        }
        background: Rectangle {
            radius: height / 2
            color: {
                const base = pill.accent ? (centre.pal.dark ? "#2a3150" : "#e2e8f5")
                           : pill.translucent ? (centre.pal.dark ? Qt.rgba(12 / 255, 15 / 255, 28 / 255, 0.72) : Qt.rgba(1, 1, 1, 0.78))
                           : centre.cardSurface;
                return pill.down ? Qt.tint(base, centre.pal.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)) : base;
            }
            border.width: pill.accent ? 0 : 1
            border.color: centre.cardEdge
        }
    }
}
