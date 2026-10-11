/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker

import "../code/launcher.js" as Launcher

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
    property string cfg_glass
    // Kicker's "Hide Application" list, edited by "Hidden apps" below: the apps chosen there are
    // shown again; apps hidden in the launcher while the page is open stay hidden (saveConfig()).
    property var cfg_hiddenApplications
    property var unhidden: []

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
    property string cfg_glassDefault

    function saveConfig() {
        const config = Plasmoid.configuration;
        cfg_favorites = config.favorites;
        cfg_favoritesPortedToKAstats = config.favoritesPortedToKAstats;
        cfg_favoritesClientId = config.favoritesClientId;
        cfg_openRequest = config.openRequest;
        cfg_hiddenApplications = Launcher.withoutUnhidden(config.hiddenApplications, page.unhidden);
        // written by the settings module and the power service
        cfg_glass = config.glass;
    }

    // Shows hidden apps again (ids as Kicker stores them, "org.kde.kcalc.desktop").
    function unhide(ids: var): void {
        unhidden = unhidden.concat(ids);
        cfg_hiddenApplications = Launcher.withoutUnhidden(cfg_hiddenApplications, ids);
    }
    readonly property var hiddenIds: Launcher.withoutUnhidden(cfg_hiddenApplications, [])

    // Names and icons of the hidden apps. The menu leaves hidden apps out, so they are looked up
    // as favourites are (an app that is no longer installed keeps its id as its name).
    Kicker.SimpleFavoritesModel {
        id: hiddenInfo
        favorites: page.hiddenIds
    }
    Instantiator {
        id: hiddenInfoReader
        model: hiddenInfo
        delegate: QtObject {
            required property string favoriteId
            required property string display
            required property var decoration
        }
    }
    function appInfo(id: string): var {
        for (let i = 0; i < hiddenInfoReader.count; ++i) {
            const entry = hiddenInfoReader.objectAt(i);
            if (entry && Launcher.appId(entry.favoriteId) === id) {
                return { "name": entry.display || id, "icon": entry.decoration || "application-x-executable" };
            }
        }
        return { "name": id.replace(/\.desktop$/, ""), "icon": "application-x-executable" };
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

        // Kicker's "Hide Application" (an app's menu in the launcher) has no list of its own to
        // undo it; "Unhide Applications in this Submenu" in the menus stays as well.
        ColumnLayout {
            id: hiddenApps
            Kirigami.FormData.label: i18nc("@label", "Hidden apps:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                visible: page.hiddenIds.length === 0
                Layout.maximumWidth: Kirigami.Units.gridUnit * 22
                wrapMode: Text.WordWrap
                text: i18nc("@info", "None. Right-click an app in the launcher and choose Hide Application to hide it.")
            }

            Repeater {
                model: page.hiddenIds
                delegate: RowLayout {
                    id: hiddenRow
                    required property string modelData
                    readonly property var info: {
                        // Re-read when the names arrive.
                        hiddenInfoReader.count;
                        return page.appInfo(modelData);
                    }
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        source: hiddenRow.info.icon
                    }
                    QQC2.Label {
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 10
                        text: hiddenRow.info.name
                        elide: Text.ElideRight
                    }
                    QQC2.Button {
                        objectName: "unhide:" + hiddenRow.modelData
                        text: i18nc("@action:button show a hidden app in the launcher again", "Show")
                        icon.name: "view-visible"
                        Accessible.name: i18nc("@action:button %1 app name", "Show %1 in the launcher", hiddenRow.info.name)
                        onClicked: page.unhide([hiddenRow.modelData])
                    }
                }
            }

            QQC2.Button {
                visible: page.hiddenIds.length > 1
                objectName: "unhideAll"
                text: i18nc("@action:button", "Show All")
                icon.name: "view-visible"
                onClicked: page.unhide(page.hiddenIds)
            }
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
