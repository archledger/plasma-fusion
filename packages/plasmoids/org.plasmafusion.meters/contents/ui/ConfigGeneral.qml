/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: page

    property bool cfg_showCpu
    property bool cfg_showCpuDefault
    property bool cfg_showMemory
    property bool cfg_showMemoryDefault
    property bool cfg_showNetwork
    property bool cfg_showNetworkDefault
    property bool cfg_showTemperature
    property bool cfg_showTemperatureDefault
    property int cfg_updateInterval
    property int cfg_updateIntervalDefault
    property int cfg_popupGap
    property int cfg_popupGapDefault
    // Hidden keys (not shown): the power service's tier and the tests' action. The dialog writes
    // every cfg_ property back on Apply, so the page hands back their current values, not the
    // ones it saw when it opened.
    property int cfg_powerTier
    property int cfg_powerTierDefault
    property string cfg_debugAction
    property string cfg_debugActionDefault

    function saveConfig(): void {
        cfg_powerTier = Plasmoid.configuration.powerTier;
        cfg_debugAction = Plasmoid.configuration.debugAction;
        cfg_popupGap = Plasmoid.configuration.popupGap;
    }

    readonly property var intervals: [
        { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 1), "value": 1000 },
        { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 2), "value": 2000 },
        { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 3), "value": 3000 },
        { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 5), "value": 5000 },
        { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 10), "value": 10000 }
    ]

    Kirigami.FormLayout {
        QQC2.CheckBox {
            Kirigami.FormData.label: i18nc("@label:checkbox group, the meters shown in the bar", "Show:")
            text: i18nc("@option:check", "Processor load")
            checked: page.cfg_showCpu
            onToggled: page.cfg_showCpu = checked
        }
        QQC2.CheckBox {
            text: i18nc("@option:check", "Memory in use")
            checked: page.cfg_showMemory
            onToggled: page.cfg_showMemory = checked
        }
        QQC2.CheckBox {
            text: i18nc("@option:check", "Download and upload rates")
            checked: page.cfg_showNetwork
            onToggled: page.cfg_showNetwork = checked
        }
        QQC2.CheckBox {
            text: i18nc("@option:check", "Processor temperature")
            checked: page.cfg_showTemperature
            onToggled: page.cfg_showTemperature = checked
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "Update every:")
            Accessible.name: i18nc("@label:listbox", "Update every")
            textRole: "label"
            valueRole: "value"
            model: page.intervals
            // Looked up in the list itself: ComboBox.indexOfValue() answers -1 until the combo has
            // read its model, and a binding on it then stays on the first entry.
            currentIndex: Math.max(0, page.intervals.findIndex(i => i.value === page.cfg_updateInterval))
            onActivated: page.cfg_updateInterval = currentValue
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18nc("@info", "The values come from Plasma's system sensors, as in System Monitor. On battery power saving the meters update less often. A temperature shows only where the processor has a sensor.")
        }
    }
}
