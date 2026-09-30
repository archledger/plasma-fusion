/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: page

    property int cfg_updateInterval
    property int cfg_updateIntervalDefault
    // Hidden key of the power service (not shown). The dialog writes every cfg_ property back on
    // Apply, so the page hands back the current tier, not the one it saw when it opened.
    property int cfg_powerTier
    property int cfg_powerTierDefault

    function saveConfig(): void {
        cfg_powerTier = Plasmoid.configuration.powerTier;
    }

    readonly property var intervals: [
        { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 1), "value": 1000 },
        { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 2), "value": 2000 },
        { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 3), "value": 3000 },
        { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 5), "value": 5000 },
        { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 10), "value": 10000 }
    ]

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "Update every:")
            textRole: "label"
            valueRole: "value"
            model: page.intervals
            // Looked up in the list itself: ComboBox.indexOfValue() answers -1 until the combo has
            // read its model, and a binding on it then stays on the first entry.
            currentIndex: Math.max(0, page.intervals.findIndex(i => i.value === page.cfg_updateInterval))
            onActivated: page.cfg_updateInterval = currentValue
        }
    }
}
