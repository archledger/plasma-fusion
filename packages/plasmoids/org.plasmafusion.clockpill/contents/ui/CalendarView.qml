/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

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

    signal closeRequested()

    // First day of the month on show. Set by showToday() (on opening) and the navigation, never
    // bound to `now`, so the month does not jump back while the user browses.
    property date shown
    Component.onCompleted: showToday()
    readonly property bool showingToday: shown.getFullYear() === now.getFullYear() && shown.getMonth() === now.getMonth()

    readonly property int contentWidth: 280
    readonly property int cellWidth: 40
    readonly property int cellHeight: 32

    // Board colours (Main / MainLight calendar and weather cards).
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color secondary: dark ? "#a3abc2" : "#5b6278"
    readonly property color tertiary: dark ? "#8f98b3" : "#6b7288"
    readonly property color dayColor: dark ? "#dfe3ee" : "#2a3044"
    readonly property color todayFill: "#2f6fdf"
    readonly property color focusColor: dark ? "#8ab8ff" : "#2f6fdf"
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
            px: 12
            weight: 700
            color: view.secondary
            text: Qt.locale().standaloneDayName(view.now.getDay(), Locale.LongFormat)
            elide: Text.ElideRight
        }
        FusionText {
            Layout.fillWidth: true
            Layout.topMargin: 2
            family: "Space Grotesk"
            px: 24
            weight: 600
            color: view.textColor
            text: Qt.locale().toString(view.now, Formats.longDateWithoutWeekday(Qt.locale().dateFormat(Locale.LongFormat)))
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.bottomMargin: 10
            implicitHeight: 1
            color: view.tint(0.08)
        }

        // ---- Month title and navigation
        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            FusionText {
                Layout.fillWidth: true
                px: 13
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
                Layout.preferredWidth: todayLabel.implicitWidth + 20
                Layout.preferredHeight: 26
                Layout.rightMargin: 4
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
                    px: 12
                    weight: 700
                    color: view.textColor
                    text: todayButton.label
                }
            }

            FlatButton {
                id: previousButton
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                label: i18nc("@action:button", "Previous month")
                onTriggered: view.moveMonths(-1)
                Chevron {
                    anchors.centerIn: parent
                    color: view.secondary
                    next: Application.layoutDirection === Qt.RightToLeft
                }
            }

            FlatButton {
                id: nextButton
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                label: i18nc("@action:button", "Next month")
                onTriggered: view.moveMonths(1)
                Chevron {
                    anchors.centerIn: parent
                    color: view.secondary
                    next: Application.layoutDirection !== Qt.RightToLeft
                }
            }
        }

        // ---- Weekday initials
        Row {
            Layout.topMargin: 8
            Layout.bottomMargin: 2
            LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
            Repeater {
                model: 7
                delegate: FusionText {
                    required property int index
                    readonly property int day: (view.weekStart + index) % 7
                    width: view.cellWidth
                    height: 20
                    horizontalAlignment: Text.AlignHCenter
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
                        width: 28
                        height: 28
                        radius: 14
                        antialiasing: true
                        color: view.todayFill
                    }
                    FusionText {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        px: 12.5
                        weight: cell.today ? 800 : 500
                        color: cell.today ? "#ffffff" : cell.weekend ? view.tertiary : view.dayColor
                        opacity: cell.inMonth || cell.today ? 1 : 0.35
                        text: cell.day.getDate()
                    }
                }
            }
        }
    }
}
