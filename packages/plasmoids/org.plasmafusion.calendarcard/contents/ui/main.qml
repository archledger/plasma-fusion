/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.workspace.dbus as DBus

// Calendar card of the Main board's desktop widgets: "September 2026" with < > arrows, narrow
// weekday initials, a compact 7-column month with today on an accent circle. The week starts on
// the region's first day (or the one chosen in the settings); weekends follow the region.
// A click on a day (or Enter on the keyboard cursor) opens KOrganizer on that date when
// KOrganizer is installed.
//
// Keys: Left/Right/Up/Down move the day cursor, Page Up/Page Down change the month, Home goes
// back to today, Enter/Space open the day, Tab reaches the arrows.
PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.StandardBackground
    preferredRepresentation: fullRepresentation
    // Text scale and pixel grid of the card (docs/parts/desktop-cards.md, "Text scale").
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
    }
    // Board card 192 x 188 minus the style's 14 px frame margins (the desktop's 16 px grid makes
    // the card 192 x 192), scaled with the text (the layout script sizes the card the same way).
    // Always the card itself: switchWidth/switchHeight would show the icon whenever the card is
    // not larger than them (libplasma appletShouldBeExpanded).
    readonly property int boardWidth: 164
    readonly property int boardHeight: 160
    readonly property real contentWidth: m.px(boardWidth)
    readonly property real contentHeight: m.px(boardHeight)

    // Today, refreshed every half minute so the circle moves at midnight (and after a resume).
    // A new day also brings the card back to today's month unless someone is browsing right
    // now: a month browsed to and left there would otherwise stay on the desktop for good.
    property date now: new Date()
    property double lastBrowsed: 0
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            const d = new Date();
            if (d.getDate() !== root.now.getDate() || d.getMonth() !== root.now.getMonth()
                    || d.getFullYear() !== root.now.getFullYear()) {
                root.now = d;
                if (Date.now() - root.lastBrowsed > 60000) {
                    root.showToday();
                }
            }
        }
    }

    // Long date without the time ("Tuesday, September 15, 2026"): Locale.toString(date,
    // Locale.LongFormat) would add the time and the time zone.
    function longDate(day: date): string {
        return Qt.locale().toString(day, Qt.locale().dateFormat(Locale.LongFormat));
    }

    readonly property int weekStart: {
        const configured = Plasmoid.configuration.firstDayOfWeek;
        return configured >= 0 && configured <= 6 ? configured : Qt.locale().firstDayOfWeek;
    }
    // Days of the week that are working days in the region (0 = Sunday); the rest is weekend.
    readonly property var workDays: Qt.locale().weekDays

    // First day of the month on show, and the keyboard cursor.
    property date shown: new Date(now.getFullYear(), now.getMonth(), 1)
    property date cursor: now
    readonly property bool showingToday: shown.getFullYear() === now.getFullYear() && shown.getMonth() === now.getMonth()

    function showToday(): void {
        shown = new Date(now.getFullYear(), now.getMonth(), 1);
        cursor = now;
    }
    function moveMonths(delta: int): void {
        lastBrowsed = Date.now();
        shown = new Date(shown.getFullYear(), shown.getMonth() + delta, 1);
        const last = new Date(shown.getFullYear(), shown.getMonth() + 1, 0).getDate();
        cursor = new Date(shown.getFullYear(), shown.getMonth(), Math.min(cursor.getDate(), last));
    }
    function moveCursor(days: int): void {
        lastBrowsed = Date.now();
        cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + days);
        if (cursor.getMonth() !== shown.getMonth() || cursor.getFullYear() !== shown.getFullYear()) {
            shown = new Date(cursor.getFullYear(), cursor.getMonth(), 1);
        }
    }

    // KOrganizer: present when its D-Bus service can be started.
    property bool korganizerAvailable: false
    function checkKOrganizer(): void {
        DBus.SessionBus.asyncCall({
            service: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus",
            member: "ListActivatableNames"
        }, reply => {
            // The callback gets the pending reply; `value` is the first return value.
            const names = reply.value;
            root.korganizerAvailable = !!names && Array.from(names).indexOf("org.kde.korganizer") !== -1;
        }, () => {
            root.korganizerAvailable = false;
        });
    }
    Component.onCompleted: checkKOrganizer()

    // Starts or raises KOrganizer (D-Bus activation) and shows the day. goDate(QString) parses
    // the text with the long date format of the same region (korganizer actionmanager.cpp).
    function openDay(day: date): void {
        if (!korganizerAvailable) {
            return;
        }
        DBus.SessionBus.asyncCall({
            service: "org.kde.korganizer",
            path: "/org/kde/korganizer",
            iface: "org.freedesktop.Application",
            member: "Activate",
            arguments: [new DBus.dict({})],
            signature: "(a{sv})"
        });
        DBus.SessionBus.asyncCall({
            service: "org.kde.korganizer",
            path: "/Calendar",
            iface: "org.kde.Korganizer.Calendar",
            member: "goDate",
            arguments: [new DBus.string(root.longDate(day))],
            signature: "(s)"
        });
    }

    readonly property string monthTitle: i18nc("@title calendar card: month and year, e.g. September 2026", "%1 %2",
                                               Qt.locale().standaloneMonthName(shown.getMonth(), Locale.LongFormat),
                                               String(shown.getFullYear()))
    Plasmoid.icon: "view-calendar"
    toolTipMainText: longDate(now)

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action", "Open KOrganizer")
            icon.name: "korganizer"
            visible: root.korganizerAvailable
            onTriggered: root.openDay(root.now)
        }
    ]

    fullRepresentation: FocusScope {
        id: card

        Accessible.role: Accessible.Pane
        Accessible.name: i18nc("@title accessible name of the calendar card", "Calendar")

        // The minimum never exceeds the board size: the desktop keeps a widget at least as large
        // as its minimum and stores the enlarged geometry, so a text size seen only for a moment
        // (the shell's font while a Global Theme is being applied) would grow the card for good.
        // The layout script gives the card the scaled size (docs/parts/desktop-cards.md).
        Layout.minimumWidth: Math.min(root.contentWidth, root.boardWidth)
        Layout.minimumHeight: Math.min(root.contentHeight, root.boardHeight)
        Layout.preferredWidth: root.contentWidth
        Layout.preferredHeight: root.contentHeight
        // 1 px of slack: the snapped sizes at fractional scales are a fraction of a pixel larger.
        readonly property real fitScale: Math.min(1, (width + 1) / root.contentWidth, (height + 1) / root.contentHeight)

        CardPalette { id: cardPalette }

        // A click anywhere on the card gives the keyboard to the month grid (arrows, Page Up/Down,
        // Home), without drawing the day cursor until a key is pressed. The TapHandler sees only
        // clicks outside the arrows, the title and the days (their MouseAreas take the others),
        // so those call it too.
        function takeKeyboard(): void {
            if (month.activeFocus) {
                month.keyboardDriven = false;
                return;
            }
            month.focusFromPointer = true;
            month.forceActiveFocus(Qt.MouseFocusReason);
            month.focusFromPointer = false;
        }
        TapHandler {
            onTapped: card.takeKeyboard()
        }

        readonly property bool rtl: Application.layoutDirection === Qt.RightToLeft
        // Board: 5 rows of 21 px with 2 px gaps. A month that needs 6 rows gets 18 px rows with
        // 1 px gaps, so the card never changes size. Rows follow the text size, gaps do not.
        readonly property int offset: (root.shown.getDay() - root.weekStart + 7) % 7
        readonly property int daysInMonth: new Date(root.shown.getFullYear(), root.shown.getMonth() + 1, 0).getDate()
        readonly property int rows: Math.ceil((offset + daysInMonth) / 7)
        readonly property real rowHeight: m.px(rows > 5 ? 18 : 21)
        readonly property int rowGap: rows > 5 ? 1 : 2

        component ChevronButton: MouseArea {
            id: chevron
            property bool next: true
            property string label
            signal triggered()

            implicitWidth: m.px(16)
            implicitHeight: m.px(16)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: label
            Accessible.onPressAction: chevron.triggered()
            onClicked: {
                card.takeKeyboard();
                chevron.triggered();
            }
            Keys.onPressed: event => {
                if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select].indexOf(event.key) !== -1) {
                    chevron.triggered();
                    event.accepted = true;
                }
            }
            PlasmaCore.ToolTipArea {
                anchors.fill: parent
                mainText: chevron.label
            }

            // Hover and pressed tint around the 16 px glyph (the board shows the glyph only).
            Rectangle {
                anchors.centerIn: parent
                width: m.px(22)
                height: m.px(22)
                radius: 7
                antialiasing: true
                color: chevron.pressed ? cardPalette.tint(0.16) : chevron.containsMouse ? cardPalette.tint(0.10) : "transparent"
            }
            LineGlyph {
                anchors.centerIn: parent
                size: m.px(16)
                color: cardPalette.label
                path: chevron.next !== card.rtl ? "M9 6l6 6-6 6" : "M15 6l-6 6 6 6"
            }
            Rectangle {
                visible: chevron.activeFocus
                anchors.centerIn: parent
                width: m.px(22) + 2
                height: m.px(22) + 2
                radius: 8
                color: "transparent"
                border.width: 2
                border.color: cardPalette.focusRing
            }
        }

        ColumnLayout {
            // Board: 14 px padding + 1 px edge; the style's frame gives 14.
            // Laid out across the card; when the desktop gave the card less than this text size
            // needs (the text size was raised after the layout was made), laid out at the size
            // it needs and scaled down to fit, so nothing is cut off.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: (card.fitScale < 1 ? root.contentWidth : parent.width) - 2 * 1
            scale: card.fitScale
            spacing: m.px(8)

            // ---- Month title and arrows
            RowLayout {
                Layout.fillWidth: true
                spacing: m.px(2)

                CardText {
                    id: titleText
                    pal: cardPalette
                    metrics: m
                    Layout.fillWidth: true
                    px: 13
                    weight: 800
                    text: root.monthTitle
                    Accessible.role: Accessible.Heading
                    Accessible.name: text

                    // Another month on show: the title leads back to today.
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.showingToday
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            card.takeKeyboard();
                            root.showToday();
                        }
                        PlasmaCore.ToolTipArea {
                            anchors.fill: parent
                            active: parent.enabled
                            mainText: i18nc("@info:tooltip", "Back to today")
                        }
                    }
                }
                // Tab order: month grid, previous, next (the grid is the card's main stop).
                ChevronButton {
                    id: previousButton
                    next: false
                    KeyNavigation.backtab: month
                    KeyNavigation.tab: nextButton
                    label: i18nc("@action:button", "Previous month")
                    onTriggered: root.moveMonths(-1)
                }
                ChevronButton {
                    id: nextButton
                    next: true
                    KeyNavigation.backtab: previousButton
                    label: i18nc("@action:button", "Next month")
                    onTriggered: root.moveMonths(1)
                }
            }

            // ---- Weekday initials (the row's width comes from the card, never from its cells)
            Item {
                id: weekdays
                Layout.fillWidth: true
                // The board's line box (10.5 px Manrope, CSS line-height normal: 14.3 px). Qt's
                // Text is 16 px high at this size, which put the days 2 px lower than the board.
                implicitHeight: m.px(14)
                readonly property real cellWidth: (width - 6 * weekdayRow.spacing) / 7
                Row {
                    id: weekdayRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    LayoutMirroring.enabled: card.rtl
                    Repeater {
                        model: 7
                        delegate: CardText {
                            required property int index
                            readonly property int day: (root.weekStart + index) % 7
                            pal: cardPalette
                            metrics: m
                            width: weekdays.cellWidth
                            horizontalAlignment: Text.AlignHCenter
                            px: 10.5
                            weight: 700
                            color: cardPalette.tertiary
                            elide: Text.ElideNone
                            text: Qt.locale().standaloneDayName(day, Locale.NarrowFormat)
                            Accessible.name: Qt.locale().standaloneDayName(day, Locale.LongFormat)
                        }
                    }
                }
            }

            // ---- Days of the month (blank cells before the 1st, as on the board)
            FocusScope {
                id: month
                Layout.fillWidth: true
                Layout.preferredHeight: card.rows * card.rowHeight + (card.rows - 1) * card.rowGap
                activeFocusOnTab: true
                Accessible.role: Accessible.Table
                Accessible.name: root.monthTitle

                // The day cursor is drawn only while the keyboard drives the grid: after Tab, or
                // after a key press once a click has focused the card. When the grid gets the
                // keyboard back unchanged (its window or the card was left and is active again:
                // the grid kept its focus in the scope meanwhile), the cursor stays as it was, so a
                // closed pop-up does not bring up a ring on a day that was only clicked.
                KeyNavigation.tab: previousButton
                property bool keyboardDriven: false
                property bool focusFromPointer: false
                property bool returning: false
                onActiveFocusChanged: {
                    if (!activeFocus) {
                        returning = focus;
                        return;
                    }
                    if (focusFromPointer) {
                        keyboardDriven = false;
                    } else if (!returning) {
                        keyboardDriven = true;
                    }
                    returning = false;
                }

                Keys.onPressed: event => {
                    month.keyboardDriven = true;
                    const step = card.rtl ? -1 : 1;
                    switch (event.key) {
                    case Qt.Key_Left:
                        root.moveCursor(-step);
                        break;
                    case Qt.Key_Right:
                        root.moveCursor(step);
                        break;
                    case Qt.Key_Up:
                        root.moveCursor(-7);
                        break;
                    case Qt.Key_Down:
                        root.moveCursor(7);
                        break;
                    case Qt.Key_PageUp:
                        root.moveMonths(-1);
                        break;
                    case Qt.Key_PageDown:
                        root.moveMonths(1);
                        break;
                    case Qt.Key_Home:
                        root.showToday();
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space:
                    case Qt.Key_Select:
                        root.openDay(root.cursor);
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }

                Grid {
                    id: grid
                    anchors.fill: parent
                    columns: 7
                    columnSpacing: 2
                    rowSpacing: card.rowGap
                    LayoutMirroring.enabled: card.rtl
                    readonly property real cellWidth: (width - 6 * columnSpacing) / 7

                    Repeater {
                        model: card.rows * 7
                        delegate: MouseArea {
                            id: cell
                            required property int index
                            readonly property int dayNumber: index - card.offset + 1
                            readonly property bool inMonth: dayNumber >= 1 && dayNumber <= card.daysInMonth
                            readonly property date day: new Date(root.shown.getFullYear(), root.shown.getMonth(), dayNumber)
                            readonly property bool today: inMonth && dayNumber === root.now.getDate()
                                                          && root.showingToday
                            readonly property bool weekend: root.workDays.indexOf(day.getDay()) === -1
                            readonly property bool isCursor: inMonth && month.activeFocus && month.keyboardDriven
                                                             && root.cursor.getFullYear() === day.getFullYear()
                                                             && root.cursor.getMonth() === day.getMonth()
                                                             && root.cursor.getDate() === dayNumber

                            width: grid.cellWidth
                            height: card.rowHeight
                            enabled: inMonth
                            hoverEnabled: inMonth && root.korganizerAvailable
                            cursorShape: hoverEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            Accessible.role: root.korganizerAvailable ? Accessible.Button : Accessible.StaticText
                            Accessible.name: inMonth ? root.longDate(day) : ""
                            onClicked: {
                                card.takeKeyboard();
                                root.cursor = day;
                                root.openDay(day);
                            }

                            readonly property real circle: Math.min(card.rowHeight, width)
                            Rectangle {
                                visible: cell.today || (cell.containsMouse && cell.hoverEnabled)
                                anchors.centerIn: parent
                                width: cell.circle
                                height: cell.circle
                                radius: width / 2
                                antialiasing: true
                                color: cell.today ? cardPalette.accent
                                                  : cell.pressed ? cardPalette.tint(0.16) : cardPalette.tint(0.10)
                            }
                            Rectangle {
                                visible: cell.isCursor
                                anchors.centerIn: parent
                                width: cell.circle + 2
                                height: cell.circle + 2
                                radius: width / 2
                                antialiasing: true
                                color: "transparent"
                                border.width: 2
                                border.color: cardPalette.focusRing
                            }
                            CardText {
                                visible: cell.inMonth
                                pal: cardPalette
                                metrics: m
                                anchors.centerIn: parent
                                px: 11.5
                                weight: cell.today ? 800 : 500
                                elide: Text.ElideNone
                                color: cell.today ? cardPalette.accentText
                                                  : cell.weekend ? cardPalette.tertiary : cardPalette.day
                                text: cell.dayNumber
                            }
                        }
                    }
                }
            }
        }
    }
}
