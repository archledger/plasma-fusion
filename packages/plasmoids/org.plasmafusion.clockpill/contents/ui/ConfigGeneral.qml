/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "../code/formats.js" as Formats

KCM.SimpleKCM {
    id: page

    property alias cfg_showWorkspaces: showWorkspaces.checked
    property alias cfg_wheelSwitchesWorkspaces: wheelSwitches.checked
    property alias cfg_showDate: showDate.checked
    property string cfg_dateFormat
    property alias cfg_customDateFormat: customDateFormat.text
    property int cfg_use24hFormat
    property int cfg_firstDayOfWeek
    property alias cfg_popupGap: popupGap.value
    property alias cfg_centerInPanel: centerInPanel.checked

    // The configuration dialog also hands every key's default value to the page.
    property bool cfg_showWorkspacesDefault
    property bool cfg_wheelSwitchesWorkspacesDefault
    property bool cfg_showDateDefault
    property string cfg_dateFormatDefault
    property string cfg_customDateFormatDefault
    property int cfg_use24hFormatDefault
    property int cfg_firstDayOfWeekDefault
    property int cfg_popupGapDefault
    property bool cfg_centerInPanelDefault

    readonly property date sample: new Date()

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: showWorkspaces
            Kirigami.FormData.label: i18nc("@title:group", "Workspaces:")
            text: i18nc("@option:check", "Show the workspace dots")
        }

        QQC2.CheckBox {
            id: wheelSwitches
            text: i18nc("@option:check", "Scroll over the pill to switch workspaces")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: showDate
            Kirigami.FormData.label: i18nc("@title:group", "Date:")
            text: i18nc("@option:check", "Show the date")
        }

        QQC2.ComboBox {
            id: dateFormat
            Accessible.name: i18nc("@label:listbox", "Date format")
            enabled: showDate.checked
            textRole: "label"
            valueRole: "value"
            model: [
                {
                    "label": i18nc("@item:inlistbox %1 is an example date", "Automatic (%1)",
                                   Qt.locale().toString(page.sample, Formats.shortDateFormat(Qt.locale(), Qt.locale().dateFormat(Locale.LongFormat)))),
                    "value": "auto"
                },
                { "label": i18nc("@item:inlistbox", "Custom"), "value": "custom" }
            ]
            // From the model itself: indexOfValue() is -1 until the model is read, which left the
            // combo on its first entry.
            currentIndex: Math.max(0, model.findIndex(entry => entry.value === page.cfg_dateFormat))
            onActivated: page.cfg_dateFormat = currentValue
        }

        RowLayout {
            visible: dateFormat.currentValue === "custom"
            enabled: showDate.checked
            QQC2.TextField {
                id: customDateFormat
                Accessible.name: i18nc("@label:textbox", "Custom date format")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            }
            QQC2.Label {
                text: Qt.locale().toString(page.sample, customDateFormat.text)
                opacity: 0.7
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: hourFormat
            Kirigami.FormData.label: i18nc("@label:listbox", "Time:")
            textRole: "label"
            valueRole: "value"
            model: [
                { "label": i18nc("@item:inlistbox", "Use region settings"), "value": 1 },
                { "label": i18nc("@item:inlistbox", "12-hour"), "value": 0 },
                { "label": i18nc("@item:inlistbox", "24-hour"), "value": 2 }
            ]
            // From the model itself: indexOfValue() is -1 until the model is read, which left the
            // combo on its first entry.
            currentIndex: Math.max(0, model.findIndex(entry => entry.value === page.cfg_use24hFormat))
            onActivated: page.cfg_use24hFormat = currentValue
        }

        QQC2.Button {
            text: i18nc("@action:button", "Change Region Settings…")
            icon.name: "preferences-desktop-locale"
            onClicked: KCM.KCMLauncher.openSystemSettings("kcm_regionandlang")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: firstDay
            Kirigami.FormData.label: i18nc("@label:listbox", "First day of week:")
            textRole: "label"
            valueRole: "value"
            model: [{ "label": i18nc("@item:inlistbox", "Use region settings"), "value": -1 }].concat(
                [0, 1, 2, 3, 4, 5, 6].map(day => ({ "label": Qt.locale().dayName(day), "value": day })))
            // From the model itself: indexOfValue() is -1 until the model is read, which left the
            // combo on its first entry.
            currentIndex: Math.max(0, model.findIndex(entry => entry.value === page.cfg_firstDayOfWeek))
            onActivated: page.cfg_firstDayOfWeek = currentValue
        }

        QQC2.CheckBox {
            id: centerInPanel
            Kirigami.FormData.label: i18nc("@title:group", "Position:")
            text: i18nc("@option:check", "Keep the pill on the middle of the panel")
        }

        RowLayout {
            Kirigami.FormData.label: i18nc("@label:spinbox", "Calendar gap:")
            QQC2.SpinBox {
                id: popupGap
                Accessible.name: i18nc("@label:spinbox", "Calendar gap")
                from: 0
                to: 40
            }
            QQC2.Label {
                text: i18nc("@label unit of the spin box", "px below the top bar")
            }
        }
    }
}
