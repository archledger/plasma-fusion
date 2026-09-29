/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.plasma.plasmoid

KCMUtils.SimpleKCM {
    id: page

    property string cfg_buttonStyle
    property alias cfg_designLabels: designLabels.checked
    property alias cfg_dimBackground: dimBackground.checked
    property alias cfg_showRecommended: showRecommended.checked
    property alias cfg_bottomOffset: bottomOffset.value

    // Keys this page does not edit. The settings dialog passes every key in and writes every
    // declared one back, so they are declared (no warnings) and refreshed from the live
    // configuration just before saving (nothing written meanwhile is overwritten).
    property var cfg_favorites
    property bool cfg_favoritesPortedToKAstats
    property string cfg_favoritesClientId
    property string cfg_openRequest
    property var cfg_hiddenApplications

    // The dialog also passes each key's default value.
    property var cfg_favoritesDefault
    property bool cfg_favoritesPortedToKAstatsDefault
    property string cfg_favoritesClientIdDefault
    property bool cfg_designLabelsDefault
    property string cfg_buttonStyleDefault
    property bool cfg_dimBackgroundDefault
    property int cfg_bottomOffsetDefault
    property bool cfg_showRecommendedDefault
    property string cfg_openRequestDefault
    property var cfg_hiddenApplicationsDefault

    function saveConfig() {
        const config = Plasmoid.configuration;
        cfg_favorites = config.favorites;
        cfg_favoritesPortedToKAstats = config.favoritesPortedToKAstats;
        cfg_favoritesClientId = config.favoritesClientId;
        cfg_openRequest = config.openRequest;
        cfg_hiddenApplications = config.hiddenApplications;
    }

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: buttonStyle
            Kirigami.FormData.label: i18nc("@label:listbox", "Panel button:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18nc("@item:inlistbox", "Automatic (tile in the dock, pill in the top bar)"), value: "auto" },
                { text: i18nc("@item:inlistbox", "Logo only"), value: "icon" },
                { text: i18nc("@item:inlistbox", "Hidden (open with Meta)"), value: "hidden" },
            ]
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_buttonStyle))
            onActivated: page.cfg_buttonStyle = currentValue
        }

        QQC2.CheckBox {
            id: designLabels
            Kirigami.FormData.label: i18nc("@label", "Pinned apps:")
            text: i18nc("@option:check", "Use short names (Files, Browser, Terminal…)")
        }

        QQC2.CheckBox {
            id: showRecommended
            text: i18nc("@option:check", "Show recently used files")
        }

        QQC2.CheckBox {
            id: dimBackground
            Kirigami.FormData.label: i18nc("@label", "Appearance:")
            text: i18nc("@option:check", "Dim the desktop while the launcher is open")
        }

        QQC2.SpinBox {
            id: bottomOffset
            Kirigami.FormData.label: i18nc("@label:spinbox", "Distance from the bottom edge:")
            from: 0
            to: 600
            textFromValue: (value, locale) => i18nc("@item:valuesuffix pixels", "%1 px", value)
        }
    }
}
