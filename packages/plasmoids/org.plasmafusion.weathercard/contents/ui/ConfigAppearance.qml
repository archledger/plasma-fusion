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

    property int cfg_titleMode
    property int cfg_temperatureUnit
    property alias cfg_updateInterval: interval.value
    property int cfg_titleModeDefault
    property int cfg_temperatureUnitDefault
    property int cfg_updateIntervalDefault
    // Keys of the location page (the settings dialog hands every key to every page).
    property string cfg_source
    property string cfg_sourceDefault
    property string cfg_placeDisplayName
    property string cfg_placeDisplayNameDefault
    property string cfg_providerName
    property string cfg_providerNameDefault

    readonly property bool metric: Qt.locale().measurementSystem !== Locale.ImperialUSSystem

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "Title:")
            textRole: "label"
            valueRole: "value"
            model: [
                { "label": i18nc("@item:inlistbox card title", "Local weather"), "value": 0 },
                { "label": i18nc("@item:inlistbox card title", "Place name"), "value": 1 }
            ]
            currentIndex: Math.max(0, indexOfValue(page.cfg_titleMode))
            onActivated: page.cfg_titleMode = currentValue
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "Temperature:")
            textRole: "label"
            valueRole: "value"
            model: [
                { "label": page.metric ? i18nc("@item:inlistbox", "From region settings (°C)")
                                       : i18nc("@item:inlistbox", "From region settings (°F)"), "value": 0 },
                { "label": i18nc("@item:inlistbox", "Celsius (°C)"), "value": 1 },
                { "label": i18nc("@item:inlistbox", "Fahrenheit (°F)"), "value": 2 }
            ]
            currentIndex: Math.max(0, indexOfValue(page.cfg_temperatureUnit))
            onActivated: page.cfg_temperatureUnit = currentValue
        }

        QQC2.SpinBox {
            id: interval
            Kirigami.FormData.label: i18nc("@label:spinbox", "Update every:")
            from: 10
            to: 180
            stepSize: 5
            textFromValue: (value, locale) => i18ncp("@item:valuesuffix", "%1 minute", "%1 minutes", value)
            valueFromText: (text, locale) => parseInt(text, 10)
        }
    }
}
