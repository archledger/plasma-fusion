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

    property alias cfg_magnify: magnify.checked
    property alias cfg_magnifiedSize: magnifiedSize.value
    property alias cfg_showTooltips: showTooltips.checked
    property alias cfg_colorVariant: colorVariant.currentIndex
    property alias cfg_tabletRecents: tabletRecents.value
    property alias cfg_searchAction: searchAction.currentIndex
    property alias cfg_showOnlyCurrentDesktop: currentDesktop.checked
    property alias cfg_showOnlyCurrentActivity: currentActivity.checked
    property alias cfg_showOnlyCurrentScreen: currentScreen.checked
    property alias cfg_minimizeActiveTaskOnClick: minimizeActive.checked

    // Keys without a control on this page. The settings dialog passes every key to the page
    // (a missing property logs "Setting initial properties failed") and writes them back on
    // Apply, so saveConfig() refreshes them first: pinning an app while the dialog is open
    // must not be undone by Apply.
    property var cfg_launchers
    property var cfg_launcherFallbacks
    property string cfg_downloadsFolder
    property string cfg_debugAction
    property int cfg_debugPointerX
    property int cfg_debugHoverIndex
    property int cfg_tabletTile
    property bool cfg_tabletShowDownloadsTrash
    property int cfg_powerTier
    property bool cfg_homeIndicator

    // The dialog also passes every key's default value as cfg_<key>Default.
    property var cfg_launchersDefault
    property var cfg_launcherFallbacksDefault
    property bool cfg_magnifyDefault
    property int cfg_magnifiedSizeDefault
    property bool cfg_showTooltipsDefault
    property int cfg_colorVariantDefault
    property int cfg_searchActionDefault
    property bool cfg_showOnlyCurrentDesktopDefault
    property bool cfg_showOnlyCurrentActivityDefault
    property bool cfg_showOnlyCurrentScreenDefault
    property bool cfg_minimizeActiveTaskOnClickDefault
    property string cfg_downloadsFolderDefault
    property string cfg_debugActionDefault
    property int cfg_debugPointerXDefault
    property int cfg_debugHoverIndexDefault
    property int cfg_tabletRecentsDefault
    property int cfg_tabletTileDefault
    property bool cfg_tabletShowDownloadsTrashDefault
    property int cfg_powerTierDefault
    property bool cfg_homeIndicatorDefault
    property int cfg_tabletStripHeight
    property int cfg_tabletStripHeightDefault

    function saveConfig(): void {
        const config = Plasmoid.configuration;
        cfg_launchers = config.launchers;
        cfg_launcherFallbacks = config.launcherFallbacks;
        cfg_downloadsFolder = config.downloadsFolder;
        cfg_debugAction = config.debugAction;
        cfg_debugPointerX = config.debugPointerX;
        cfg_debugHoverIndex = config.debugHoverIndex;
        cfg_tabletTile = config.tabletTile;
        cfg_tabletShowDownloadsTrash = config.tabletShowDownloadsTrash;
        // written by the power tiers service while the dialog may be open
        cfg_powerTier = config.powerTier;
        // the settings module's switch
        cfg_homeIndicator = config.homeIndicator;
        // written by the tablet KWin script
        cfg_tabletStripHeight = config.tabletStripHeight;
    }

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: magnify
            Kirigami.FormData.label: i18nc("@title:group", "Icons:")
            text: i18nc("@option:check", "Magnify icons on hover")
        }

        RowLayout {
            Kirigami.FormData.label: i18nc("@label:spinbox", "Magnified size:")
            enabled: magnify.checked
            QQC2.SpinBox {
                id: magnifiedSize
                Accessible.name: i18nc("@label:spinbox", "Magnified size")
                from: 48
                to: 72
                stepSize: 2
            }
            QQC2.Label {
                text: i18nc("@label unit of the spin box", "px (icons rest at 48 px)")
            }
        }

        QQC2.CheckBox {
            id: showTooltips
            text: i18nc("@option:check", "Show app names above the hovered icon")
        }

        RowLayout {
            Kirigami.FormData.label: i18nc("@label:spinbox", "Recent apps in tablet posture:")
            QQC2.SpinBox {
                id: tabletRecents
                Accessible.name: i18nc("@label:spinbox", "Recent apps in tablet posture")
                from: 0
                to: 3
            }
            QQC2.Label {
                text: i18nc("@label after the spin box", "after the pinned apps, most recently used first")
            }
        }

        QQC2.ComboBox {
            id: colorVariant
            Kirigami.FormData.label: i18nc("@label:listbox", "Colours:")
            model: [
                i18nc("@item:inlistbox", "Follow the Plasma style"),
                i18nc("@item:inlistbox", "Dark"),
                i18nc("@item:inlistbox", "Light")
            ]
        }

        QQC2.ComboBox {
            id: searchAction
            Kirigami.FormData.label: i18nc("@label:listbox", "Search button opens:")
            model: [
                i18nc("@item:inlistbox", "KRunner"),
                i18nc("@item:inlistbox", "The application launcher")
            ]
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: currentDesktop
            Kirigami.FormData.label: i18nc("@title:group", "Running apps:")
            text: i18nc("@option:check", "Only from the current virtual desktop")
        }

        QQC2.CheckBox {
            id: currentActivity
            text: i18nc("@option:check", "Only from the current activity")
        }

        QQC2.CheckBox {
            id: currentScreen
            text: i18nc("@option:check", "Only from the screen of the dock")
        }

        QQC2.CheckBox {
            id: minimizeActive
            text: i18nc("@option:check", "Clicking the active app minimizes it")
        }
    }
}
