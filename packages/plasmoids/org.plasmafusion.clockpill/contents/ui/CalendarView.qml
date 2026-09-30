/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "../code/formats.js" as Formats

// Calendar pop-up of the clock pill. There is no board for it; it follows the desktop calendar
// card of the Main board (month title 13 px 800, 16 px chevrons, narrow weekday row 10.5 px
// 700, today on a #2f6fdf circle in white 800) inside the frosted pop-up surface of the
// Plasma style, with a header naming today like the weather card ("Local weather" label style
// above a Space Grotesk figure).
//
// Keys: Left/Right or Page Up/Page Down change the month, Home returns to today, Esc closes.
FocusScope {
    id: view

    required property date now
    required property int firstDayOfWeek
    required property bool dark
    // Touch sizes (ADAPTIVE 5.2, TABLET 4.7): 44 x 44 day cells in a 308 px grid, 44 px buttons,
    // a 17 px month title.
    property bool touch: false
    property Motion motion: null

    signal closeRequested()

    // First day of the month on show. Set by showToday() (on opening) and the navigation, never
    // bound to `now`, so the month does not jump back while the user browses.
    property date shown
    Component.onCompleted: showToday()
    readonly property bool showingToday: shown.getFullYear() === now.getFullYear() && shown.getMonth() === now.getMonth()

    // Text scale and pixel grid of the pop-up window (docs/parts/shell-topbar.md, "Text scale").
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
    }

    // Board: 280 px wide, day cells 40 x 32 in six rows, scaled with the text. The cells divide
    // the snapped width and grid height, so the grid stays exactly as wide as the pop-up. Touch:
    // 7 x 44 = 308 px, square cells.
    readonly property real contentWidth: touch ? Math.max(308, m.px(280)) : m.px(280)
    readonly property real cellWidth: contentWidth / 7
    readonly property real cellHeight: touch ? Math.max(44, m.px(32)) : m.px(6 * 32) / 6
    readonly property real buttonSize: touch ? 44 : m.px(26)

    // Board colours (Main / MainLight calendar and weather cards).
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color secondary: dark ? "#a3abc2" : "#5b6278"
    readonly property color tertiary: dark ? "#8f98b3" : "#6b7288"
    readonly property color dayColor: dark ? "#dfe3ee" : "#2a3044"
    // The user's accent (decision 3).
    FusionAccent {
        id: accent
    }
    readonly property color todayFill: accent.fill
    readonly property color focusColor: accent.focusRing
    readonly property color ink: dark ? "#ffffff" : Kirigami.Theme.textColor
    function tint(alpha: real): color {
        return Qt.rgba(ink.r, ink.g, ink.b, alpha);
    }

    readonly property int weekStart: firstDayOfWeek >= 0 && firstDayOfWeek <= 6 ? firstDayOfWeek : Qt.locale().firstDayOfWeek
    readonly property var workDays: Qt.locale().weekDays

    implicitWidth: contentWidth
    implicitHeight: column.implicitHeight
    Layout.minimumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight
    Layout.maximumHeight: implicitHeight

    function showToday() {
        shown = new Date(now.getFullYear(), now.getMonth(), 1);
    }
    function moveMonths(delta: int) {
        shown = new Date(shown.getFullYear(), shown.getMonth() + delta, 1);
    }

    // Day shown in grid cell `index` (0..41), starting on the first day of the week.
    function dayAt(index: int): date {
        const offset = (shown.getDay() - weekStart + 7) % 7;
        return new Date(shown.getFullYear(), shown.getMonth(), 1 - offset + index);
    }

    Keys.onPressed: event => {
        const rtl = Application.layoutDirection === Qt.RightToLeft;
        switch (event.key) {
        case Qt.Key_Left:
            moveMonths(rtl ? 1 : -1);
            break;
        case Qt.Key_Right:
            moveMonths(rtl ? -1 : 1);
            break;
        case Qt.Key_PageUp:
            moveMonths(-1);
            break;
        case Qt.Key_PageDown:
            moveMonths(1);
            break;
        case Qt.Key_Home:
            showToday();
            break;
        case Qt.Key_Escape:
            view.closeRequested();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    component FlatButton: MouseArea {
        id: flat
        property string label
        property real radius: 8
        default property alias content: contentHolder.data

        signal triggered()

        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: flat.triggered()
        onClicked: flat.triggered()
        Keys.onPressed: event => {
            if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select].indexOf(event.key) !== -1) {
                flat.triggered();
                event.accepted = true;
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: flat.radius
            antialiasing: true
            color: flat.pressed ? view.tint(0.16) : flat.containsMouse ? view.tint(0.10) : "transparent"
        }
        Item {
            id: contentHolder
            anchors.fill: parent
        }
        Rectangle {
            visible: flat.activeFocus
            anchors.fill: parent
            anchors.margins: -4
            radius: flat.radius + 4
            color: "transparent"
            border.width: 2
            border.color: view.focusColor
        }
    }

    ColumnLayout {
        id: column
        width: view.contentWidth
        spacing: 0

        // ---- Today
        FusionText {
            Layout.fillWidth: true
            metrics: m
            px: 12
            weight: 700
            color: view.secondary
            text: Qt.locale().standaloneDayName(view.now.getDay(), Locale.LongFormat)
            elide: Text.ElideRight
        }
        FusionText {
            Layout.fillWidth: true
            Layout.topMargin: m.px(2)
            metrics: m
            display: true
            px: 24
            weight: 600
            color: view.textColor
            text: Qt.locale().toString(view.now, Formats.longDateWithoutWeekday(Qt.locale().dateFormat(Locale.LongFormat)))
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: m.px(12)
            Layout.bottomMargin: m.px(10)
            implicitHeight: 1
            color: view.tint(0.08)
        }

        // ---- Month title and navigation
        RowLayout {
            Layout.fillWidth: true
            spacing: m.px(2)

            FusionText {
                Layout.fillWidth: true
                metrics: m
                px: view.touch ? 17 : 13
                weight: 800
                color: view.textColor
                text: Qt.locale().standaloneMonthName(view.shown.getMonth(), Locale.LongFormat) + " " + view.shown.getFullYear()
                elide: Text.ElideRight
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            FlatButton {
                id: todayButton
                visible: !view.showingToday
                Layout.preferredWidth: Math.max(todayLabel.implicitWidth + m.px(20), view.touch ? 44 : 0)
                Layout.preferredHeight: view.buttonSize
                Layout.rightMargin: m.px(4)
                label: i18nc("@action:button go to the current month", "Today")
                onTriggered: view.showToday()

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: view.tint(0.08)
                }
                FusionText {
                    id: todayLabel
                    anchors.centerIn: parent
                    metrics: m
                    px: 12
                    weight: 700
                    color: view.textColor
                    text: todayButton.label
                }
            }

            FlatButton {
                id: previousButton
                Layout.preferredWidth: view.buttonSize
                Layout.preferredHeight: view.buttonSize
                label: i18nc("@action:button", "Previous month")
                onTriggered: view.moveMonths(-1)
                Chevron {
                    anchors.centerIn: parent
                    size: m.px(16)
                    color: view.secondary
                    next: Application.layoutDirection === Qt.RightToLeft
                }
            }

            FlatButton {
                id: nextButton
                Layout.preferredWidth: view.buttonSize
                Layout.preferredHeight: view.buttonSize
                label: i18nc("@action:button", "Next month")
                onTriggered: view.moveMonths(1)
                Chevron {
                    anchors.centerIn: parent
                    size: m.px(16)
                    color: view.secondary
                    next: Application.layoutDirection !== Qt.RightToLeft
                }
            }
        }

        // ---- Weekday initials
        Row {
            Layout.topMargin: m.px(8)
            Layout.bottomMargin: m.px(2)
            LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
            Repeater {
                model: 7
                delegate: FusionText {
                    required property int index
                    readonly property int day: (view.weekStart + index) % 7
                    width: view.cellWidth
                    height: m.px(20)
                    horizontalAlignment: Text.AlignHCenter
                    metrics: m
                    px: 10.5
                    weight: 700
                    color: view.tertiary
                    text: Qt.locale().standaloneDayName(day, Locale.NarrowFormat)
                    Accessible.name: Qt.locale().standaloneDayName(day, Locale.LongFormat)
                }
            }
        }

        // ---- Days: always six weeks so the pop-up keeps its size between months
        Grid {
            columns: 7
            LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
            Repeater {
                model: 42
                delegate: Item {
                    id: cell
                    required property int index
                    readonly property date day: view.dayAt(index)
                    readonly property bool inMonth: day.getMonth() === view.shown.getMonth()
                    readonly property bool today: day.getFullYear() === view.now.getFullYear()
                                                  && day.getMonth() === view.now.getMonth()
                                                  && day.getDate() === view.now.getDate()
                    readonly property bool weekend: view.workDays.indexOf(day.getDay()) === -1

                    width: view.cellWidth
                    height: view.cellHeight
                    Accessible.role: Accessible.StaticText
                    Accessible.name: Qt.locale().toString(day, Locale.LongFormat)

                    Rectangle {
                        visible: cell.today
                        anchors.centerIn: parent
                        width: view.touch ? 36 : m.px(28)
                        height: width
                        radius: width / 2
                        antialiasing: true
                        color: view.todayFill
                    }
                    FusionText {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        metrics: m
                        px: 12.5
                        weight: cell.today ? 800 : 500
                        color: cell.today ? accent.fillText : cell.weekend ? view.tertiary : view.dayColor
                        font.features: { "tnum": 1 }
                        opacity: cell.inMonth || cell.today ? 1 : 0.35
                        text: cell.day.getDate()
                    }
                }
            }
        }
    }
}
