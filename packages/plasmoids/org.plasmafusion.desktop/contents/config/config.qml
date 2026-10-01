/*
    SPDX-FileCopyrightText: 2014-2015 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.plasma.plasmoid
import org.kde.plasma.configuration

ConfigModel {
    id: configModel
    // Plasma Fusion: the fork is always the Folder View variant (upstream tells the two plugin ids
    // of one package apart by name)
    property bool isFolder: (Plasmoid.pluginName === "org.kde.plasma.folder" || Plasmoid.pluginName === "org.plasmafusion.desktop")

    ConfigCategory {
         name: i18nc("@title:group for configuration dialog page", "Location")
         icon: "inode-directory"
         source: "ConfigLocation.qml"
         visible: configModel.isFolder
    }

    ConfigCategory {
         name: i18nc("@title:group for configuration dialog page", "Icons")
         icon: "preferences-desktop-icons"
         source: "ConfigIcons.qml"
         visible: configModel.isFolder
    }

    ConfigCategory {
         name: i18nc("@title:group for configuration dialog page", "Filter")
         icon: "preferences-desktop-filter"
         source: "ConfigFilter.qml"
         visible: configModel.isFolder
    }
}
