/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.sessions as Sessions
import org.kde.plasma.workspace.dbus as DBus

import "../code/launcher.js" as Launcher

// The launcher in tablet posture (TABLET 4.5): a full-screen app grid over the Tinted backdrop.
// Search pill 560 x 48 under the top bar (not focused on open, so no keyboard appears), session
// buttons 44 px beside it, pages of 128 x 120 cells with 72 px icons (7 columns, 5 in portrait or
// on a narrow screen, 4 below 700 px; rows fill the height above the dock's 128 px reserve), page 1
// the pinned apps, then all apps; page dots; search results replace the grid and end above the
// on-screen keyboard. A horizontal swipe changes the page, a swipe down (96 px or 800 px/s) or a
// tap on empty space closes; the content follows the finger. `progress` (0 closed, 1 open)
// drives the backdrop's opacity and the content's scale and offset, from the open animation or
// from the dock's swipe (beginReveal / updateReveal / endReveal in main.qml).
FocusScope {
    id: sheet

    required property var launcher
    required property FusionColors pal
    required property FusionMetrics metrics
    required property Motion motion
    // Height of the top bar (the sheet starts under it) and the wallpaper's screen.
    property real topBar: 44
    property int screenNumber: 0
    // Shown (the icon delegates exist only then).
    property bool shown: false
    property real progress: 0
    property real dragDown: 0

    signal closeRequested()

    Accessible.role: Accessible.Pane
    Accessible.name: i18nc("@title accessible name of the tablet launcher", "Apps")

    readonly property int cellWidth: 128
    readonly property int cellHeight: 120
    readonly property int columns: width < 700 ? 4 : (metrics.portrait || metrics.compactWidth ? 5 : 7)
    readonly property int rows: Math.max(1, Math.min(7, Math.floor((height - topBar - 24 - 48 - 52 - 36 - 128) / cellHeight)))
    readonly property int perPage: columns * rows
    readonly property var favoritesModel: launcher ? launcher.favoritesModel : null
    readonly property var allModel: launcher ? launcher.allAppsModel() : null
    readonly property int allCount: allModel ? allModel.count : 0
    readonly property int pageCount: 1 + Math.ceil(allCount / Math.max(1, perPage))
    readonly property bool searching: search.text.length > 0
    readonly property real pillY: topBar + 24
    readonly property real gridY: pillY + 48 + 52
    readonly property real gridWidth: columns * cellWidth
    readonly property real gridHeight: rows * cellHeight
    readonly property alias currentPage: pages.currentIndex

    function reset() {
        // The field gives up the focus: the next open must not bring up the keyboard.
        search.focus = false;
        search.text = "";
        pages.positionViewAtIndex(0, ListView.Beginning);
        pages.currentIndex = 0;
        dragDown = 0;
        sheet.forceActiveFocus();
    }

    // Opened for a search (the home screen's swipe down, TABLET2 H2): the field takes the focus, so
    // the on-screen keyboard comes up as on iPadOS and Android.
    function focusSearch(text: string): void {
        search.text = text;
        search.cursorPosition = text.length;
        search.forceActiveFocus();
    }

    Keys.onEscapePressed: {
        if (searching) {
            search.text = "";
            sheet.forceActiveFocus();
        } else {
            closeRequested();
        }
    }
    // Typing on a keyboard searches (the pill is not focused on open).
    Keys.onPressed: event => {
        if (!search.activeFocus && Launcher.isPrintable(event.text)
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            search.forceActiveFocus();
            search.insert(search.cursorPosition, event.text);
            event.accepted = true;
        }
    }

    // ---- Backdrop (the Tinted material, no live blur) and tap on empty space
    FusionBackdrop {
        anchors.fill: parent
        followWallpaper: true
        screenNumber: sheet.screenNumber
        dark: sheet.pal.dark
        opacity: sheet.progress * (1 - Math.min(1, sheet.dragDown / 400))
    }
    TapHandler {
        onTapped: sheet.closeRequested()
    }

    // ---- The on-screen keyboard's top (search results end above it)
    // Qt's keyboard rectangle when KWin reports it, else plasma-keyboard's height rule while KWin
    // shows its keyboard (TABLET 4.5).
    property bool oskVisible: false
    function refreshOsk() {
        DBus.SessionBus.asyncCall({
            "service": "org.kde.KWin", "path": "/VirtualKeyboard", "iface": "org.freedesktop.DBus.Properties",
            "member": "Get", "arguments": [new DBus.string("org.kde.kwin.VirtualKeyboard"), new DBus.string("visible")],
            "signature": "(ss)"
        }, reply => sheet.oskVisible = reply.value === true, () => {});
    }
    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.kde.KWin"
        path: "/VirtualKeyboard"
        iface: "org.kde.kwin.VirtualKeyboard"
        function dbusvisibleChanged() {
            sheet.refreshOsk();
        }
        // KWin's other signals on this interface; without a handler the watcher logs a warning for
        // each (about a thousand a day in tablet use, field log 2026-10-02).
        function dbusactiveChanged() {
        }
        function dbusactiveClientSupportsTextInputChanged() {
        }
        function dbusavailableChanged() {
        }
        function dbusmodeChanged() {
        }
    }
    readonly property real keyboardTop: {
        // qmllint disable missing-property
        const rect = Qt.inputMethod.keyboardRectangle;
        // qmllint enable missing-property
        if (rect.height > 0) {
            return rect.y;
        }
        return oskVisible ? height - Math.max(0.3 * height, 150) : height;
    }

    Item {
        id: content
        width: sheet.width
        height: sheet.height
        opacity: Math.min(1, sheet.progress * 1.4) * (1 - Math.min(1, sheet.dragDown / 400))
        scale: 0.96 + 0.04 * sheet.progress
        transform: Translate {
            y: 24 * (1 - sheet.progress) + sheet.dragDown
        }

        // Search pill: 560 x 48, radius 24, centred. The session buttons end at the grid's right
        // edge; where a centred 560 px pill would reach them it is narrower, and where that would
        // leave less than 320 px (portrait) it starts at the grid's left edge instead.
        Rectangle {
            id: pill
            readonly property real room: sessionRow.x - 16
            readonly property real centredWidth: Math.min(560, 2 * (room - sheet.width / 2))
            readonly property bool centred: centredWidth >= 320
            readonly property real gridLeft: (sheet.width - sheet.gridWidth) / 2
            width: centred ? centredWidth : Math.max(160, Math.min(560, room - gridLeft))
            height: 48
            x: centred ? (sheet.width - width) / 2 : gridLeft
            y: sheet.pillY
            radius: 24
            // The field inside is the accessible control; the pill only forwards a tap to it.
            Accessible.ignored: true
            color: sheet.pal.tint(0.10)
            border.width: 1
            border.color: search.activeFocus ? sheet.pal.fieldBorder : sheet.pal.tint(0.14)

            Glyph {
                id: searchGlyph
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 20
                color: sheet.pal.textSecondary
            }
            TextInput {
                id: search
                objectName: "sheetSearch"
                anchors.left: searchGlyph.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: sheet.pal.text
                selectionColor: sheet.pal.accent
                selectedTextColor: "#ffffff"
                font.family: sheet.metrics.family
                font.pixelSize: sheet.metrics.font(15)
                inputMethodHints: Qt.ImhNoPredictiveText
                Accessible.role: Accessible.EditableText
                Accessible.name: i18nc("@label:textbox", "Search")
                Accessible.searchEdit: true
                onTextChanged: {
                    if (sheet.launcher) {
                        sheet.launcher.searchText = text;
                    }
                }
                Keys.onReturnPressed: results.launch(Math.max(0, results.currentIndex))
                Keys.onEnterPressed: results.launch(Math.max(0, results.currentIndex))
                Keys.onDownPressed: {
                    if (results.count > 0) {
                        results.keyboardNavigation = true;
                        results.forceActiveFocus(Qt.TabFocusReason);
                    }
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text.length === 0 && !search.preeditText
                    text: i18nc("@info:placeholder", "Search apps, files and settings")
                    color: sheet.pal.placeholder
                    elide: Text.ElideRight
                    font.family: sheet.metrics.family
                    font.pixelSize: sheet.metrics.font(15)
                    font.weight: Font.DemiBold
                }
            }
            // A tap focuses the field (the keyboard then appears). Exclusive, so the sheet's own
            // tap handler (empty space closes) does not see it.
            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: search.forceActiveFocus(Qt.MouseFocusReason)
            }
        }

        // Session buttons, right-aligned to the grid, centred on the pill.
        Sessions.SessionManagement {
            id: session
        }
        Row {
            id: sessionRow
            x: Math.min(sheet.width - 16, (sheet.width + sheet.gridWidth) / 2) - width
            y: pill.y + (pill.height - height) / 2
            spacing: 12
            visible: !sheet.searching || sheet.width >= 1100
            RoundButton {
                pal: sheet.pal
                size: 44
                glyph: "lock"
                text: i18nc("@action:button", "Lock")
                enabled: session.canLock
                onClicked: {
                    sheet.closeRequested();
                    session.lock();
                }
            }
            RoundButton {
                pal: sheet.pal
                size: 44
                glyph: "sleep"
                text: i18nc("@action:button", "Sleep")
                enabled: session.canSuspend
                onClicked: {
                    sheet.closeRequested();
                    session.suspend();
                }
            }
            RoundButton {
                pal: sheet.pal
                size: 44
                glyph: "restart"
                text: i18nc("@action:button", "Restart")
                enabled: session.canReboot
                onClicked: {
                    sheet.closeRequested();
                    session.requestReboot();
                }
            }
            RoundButton {
                pal: sheet.pal
                size: 44
                glyph: "power"
                danger: true
                text: i18nc("@action:button", "Shut Down")
                enabled: session.canShutdown
                onClicked: {
                    sheet.closeRequested();
                    session.requestShutdown();
                }
            }
        }

        // Page title, 20 px above the grid.
        FusionText {
            x: (sheet.width - sheet.gridWidth) / 2 + 8
            y: sheet.gridY - 20 - height
            visible: !sheet.searching
            text: pages.currentIndex === 0 ? i18nc("@title", "Pinned") : i18nc("@title", "All apps")
            color: sheet.pal.text
            metrics: sheet.metrics
            px: 17
            weight: 800
        }

        // Pages: page 1 the pins, then all apps alphabetically.
        ListView {
            id: pages
            objectName: "sheetPages"
            x: (sheet.width - width) / 2
            y: sheet.gridY
            width: sheet.gridWidth
            height: sheet.gridHeight
            visible: !sheet.searching
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            highlightMoveDuration: sheet.motion.surface
            clip: true
            cacheBuffer: 0
            model: sheet.shown ? sheet.pageCount : 0
            Accessible.role: Accessible.PageTabList
            Accessible.name: i18nc("@label", "App pages")

            delegate: GridView {
                id: page
                required property int index
                readonly property int start: index === 0 ? 0 : (index - 1) * sheet.perPage
                width: pages.width
                height: pages.height
                cellWidth: sheet.cellWidth
                cellHeight: sheet.cellHeight
                interactive: false
                Accessible.role: Accessible.List
                model: KItemModels.KSortFilterProxyModel {
                    sourceModel: page.index === 0 ? sheet.favoritesModel : sheet.allModel
                    filterRowCallback: (row, parent) => row >= page.start && row < page.start + sheet.perPage
                }
                delegate: SheetTile {
                    owner: sheet
                    pageView: page
                }
            }
        }

        // Page dots: 8 x 8, the current one 20 x 8, 10 apart, 12 px under the grid; tappable.
        Row {
            id: dots
            x: (sheet.width - width) / 2
            y: pages.y + pages.height + 12
            spacing: 10
            visible: !sheet.searching && sheet.pageCount > 1
            Repeater {
                model: sheet.pageCount
                delegate: Item {
                    id: dotCell
                    required property int index
                    width: dot.width
                    height: 8
                    Rectangle {
                        id: dot
                        width: dotCell.index === pages.currentIndex ? 20 : 8
                        height: 8
                        radius: 4
                        color: sheet.pal.tint(dotCell.index === pages.currentIndex ? 0.8 : 0.3)
                        Behavior on width {
                            enabled: sheet.motion.animate
                            NumberAnimation { duration: sheet.motion.toggle; easing.type: sheet.motion.standardEasing }
                        }
                    }
                    // The hit row is 44 px tall.
                    TapHandler {
                        margin: 18
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: pages.currentIndex = dotCell.index
                    }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: i18nc("@action:button %1 page number", "Page %1", dotCell.index + 1)
                }
            }
        }

        // Search results: rows 56 px, at most 720 wide, above the keyboard.
        ResultsList {
            id: results
            x: (sheet.width - width) / 2
            y: sheet.pillY + 48 + 24
            width: Math.min(720, sheet.width - 32)
            height: Math.max(120, Math.min(sheet.height - 128, sheet.keyboardTop - 16) - y)
            visible: sheet.searching
            pal: sheet.pal
            metrics: sheet.metrics
            launcher: sheet.launcher
            model: sheet.launcher && sheet.searching && sheet.launcher.runnerModel.count > 0 ? sheet.launcher.runnerModel.modelForRow(0) : null
            onExitTop: search.forceActiveFocus()
            onTyped: text => {
                search.forceActiveFocus();
                if (text === "\b") {
                    search.remove(Math.max(0, search.cursorPosition - 1), search.cursorPosition);
                } else {
                    search.insert(search.cursorPosition, text);
                }
            }
            onCountChanged: {
                if (sheet.launcher) {
                    sheet.launcher.noteResults(count);
                }
            }
        }
    }

    // ---- Swipe down on the grid closes; the content follows the finger. In a layer above the
    // tiles: there the handler sees the touch first and holds only a passive grab until the
    // threshold, so taps and horizontal flicks still reach the tiles and the pages.
    Item {
        anchors.fill: parent
        anchors.topMargin: sheet.gridY
        z: 100
        DragHandler {
            id: swipeDown
            acceptedDevices: PointerDevice.TouchScreen
            target: null
            xAxis.enabled: false
            dragThreshold: 16
            onTranslationChanged: {
                if (active) {
                    sheet.dragDown = Math.max(0, translation.y);
                }
            }
            onActiveChanged: {
                if (active) {
                    return;
                }
                if (sheet.dragDown >= 96 || centroid.velocity.y >= 800) {
                    console.info("launcher: sheet swipe down closes");
                    sheet.closeRequested();
                } else {
                    dragBack.start();
                }
            }
        }
    }
    NumberAnimation {
        id: dragBack
        target: sheet
        property: "dragDown"
        to: 0
        duration: sheet.motion.popupOut
        easing.type: sheet.motion.standardEasing
    }

    // ---- One cell: the whole cell is the target; a long press opens the app's menu.
    component SheetTile: T.AbstractButton {
        id: tile
        // The sheet and the page's grid (an inline component sees no ids of this file).
        required property var owner
        required property var pageView
        required property int index
        required property var model
        readonly property int sourceRow: pageView.start + index

        width: 128
        height: 120
        hoverEnabled: true
        text: tile.model.display || ""
        Accessible.role: Accessible.Button
        Accessible.name: text

        onClicked: {
            const source = pageView.index === 0 ? tile.owner.favoritesModel : tile.owner.allModel;
            if (source) {
                tile.owner.launcher.playLaunchZoom(icon, tile.model.decoration || "application-x-executable", Launcher.iconNameFor(tile.model));
            }
            if (source && source.trigger(tile.sourceRow, "", null)) {
                tile.owner.launcher.close();
            }
        }
        onPressAndHold: {
            const source = pageView.index === 0 ? tile.owner.favoritesModel : tile.owner.allModel;
            tile.owner.launcher.openActionMenu(source, tile.sourceRow, tile.model, tile, width / 2, height / 2);
        }

        background: Rectangle {
            radius: 16
            color: tile.down || tile.hovered ? tile.owner.pal.tileHover : "transparent"
        }
        contentItem: Item {
            FusionShadow {
                anchors.fill: icon
                offset.y: 3
                blur: 6
                radius: 0.234 * icon.size
                color: tile.owner.pal.iconShadow
            }
            FusionIconTile {
                id: icon
                x: (parent.width - width) / 2
                y: Math.round((parent.height - (72 + 10 + label.height)) / 2)
                size: 72
                source: tile.model.decoration || "application-x-executable"
                iconName: Launcher.iconNameFor(tile.model)
            }
            FusionText {
                id: label
                anchors.top: icon.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 8
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                text: tile.text
                color: tile.owner.pal.tileText
                metrics: tile.owner.metrics
                px: 13
                weight: 600
            }
        }
    }
}
