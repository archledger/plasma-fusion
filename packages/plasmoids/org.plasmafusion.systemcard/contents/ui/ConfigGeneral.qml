/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property int cfg_updateInterval
    property int cfg_updateIntervalDefault

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "Update every:")
            textRole: "label"
            valueRole: "value"
            model: [
                { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 1), "value": 1000 },
                { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 2), "value": 2000 },
                { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 5), "value": 5000 },
                { "label": i18ncp("@item:inlistbox", "%1 second", "%1 seconds", 10), "value": 10000 }
            ]
            currentIndex: Math.max(0, indexOfValue(page.cfg_updateInterval))
            onActivated: page.cfg_updateInterval = currentValue
        }
    }
}
