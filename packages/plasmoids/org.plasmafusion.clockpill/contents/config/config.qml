/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.configuration
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.calendar as PlasmaCalendar

ConfigModel {
    id: configModel
    ConfigCategory {
        name: i18nc("@title", "General")
        icon: "preferences-system-time"
        source: "ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18nc("@title", "Calendar")
        icon: "office-calendar"
        source: "ConfigCalendar.qml"
    }
    ConfigCategory {
        name: i18nc("@title", "Time zones")
        icon: "preferences-system-time"
        source: "ConfigTimeZones.qml"
    }
    // Provider-specific resource pages are owned by KDE, including the PIM calendar selector.
    readonly property PlasmaCalendar.EventPluginsManager providers: PlasmaCalendar.EventPluginsManager {
        Component.onCompleted: populateEnabledPluginsList(Plasmoid.configuration.enabledCalendarPlugins)
    }
    readonly property Instantiator providerPages: Instantiator {
        model: configModel.providers.model
        delegate: ConfigCategory {
            required property string display
            required property string decoration
            required property string configUi
            required property string configModule
            required property string configComponent
            required property string pluginId
            name: display
            icon: decoration
            source: configUi
            configUiModule: configModule
            configUiComponent: configComponent
            visible: Plasmoid.configuration.enabledCalendarPlugins.indexOf(pluginId) !== -1
        }
        onObjectAdded: (index, object) => configModel.appendCategory(object)
        onObjectRemoved: (index, object) => configModel.removeCategory(object)
    }
}
