// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.calendar as PlasmaCalendar

KCM.SimpleKCM {
    id: page
    property var cfg_enabledCalendarPlugins: []
    property var cfg_enabledCalendarPluginsDefault: []
    // Every key of main.xml needs a cfg_ property on every page, and its default a
    // cfg_<key>Default, or the settings dialog warns ("Setting initial properties failed").
    // Keys this page does not edit (the other pages' and the widget's own). The dialog writes
    // every declared key back on Apply, so they are refreshed from the live configuration just
    // before saving (nothing written meanwhile is lost).
    property bool cfg_showWorkspaces: true
    property bool cfg_wheelSwitchesWorkspaces: true
    property bool cfg_showDate: true
    property string cfg_dateFormat: "auto"
    property string cfg_customDateFormat: "ddd d MMM"
    property int cfg_use24hFormat: 1
    property bool cfg_showSeconds: false
    property var cfg_selectedTimeZones: ["Local"]
    property int cfg_firstDayOfWeek: -1
    property bool cfg_centerInPanel: true
    property bool cfg_widthBudget: true
    property string cfg_menuPolicy: "centre"
    property bool cfg_menuSearch: false
    property bool cfg_menuCompacted: false
    property string cfg_debugAction: ""
    property int cfg_popupGap: 10

    property bool cfg_showWorkspacesDefault
    property bool cfg_wheelSwitchesWorkspacesDefault
    property bool cfg_showDateDefault
    property string cfg_dateFormatDefault
    property string cfg_customDateFormatDefault
    property int cfg_use24hFormatDefault
    property bool cfg_showSecondsDefault
    property var cfg_selectedTimeZonesDefault: ["Local"]
    property int cfg_firstDayOfWeekDefault
    property bool cfg_centerInPanelDefault
    property bool cfg_widthBudgetDefault
    property string cfg_menuPolicyDefault
    property bool cfg_menuSearchDefault
    property bool cfg_menuCompactedDefault
    property string cfg_debugActionDefault
    property int cfg_popupGapDefault

    function saveConfig() {
        const config = Plasmoid.configuration;
        // edited on the General page
        cfg_showWorkspaces = config.showWorkspaces;
        cfg_wheelSwitchesWorkspaces = config.wheelSwitchesWorkspaces;
        cfg_showDate = config.showDate;
        cfg_dateFormat = config.dateFormat;
        cfg_customDateFormat = config.customDateFormat;
        cfg_use24hFormat = config.use24hFormat;
        cfg_showSeconds = config.showSeconds;
        cfg_firstDayOfWeek = config.firstDayOfWeek;
        cfg_centerInPanel = config.centerInPanel;
        cfg_menuSearch = config.menuSearch;
        cfg_popupGap = config.popupGap;
        // edited on the Time zones page
        cfg_selectedTimeZones = config.selectedTimeZones;
        // no control in the dialog; the width budget writes menuCompacted itself, desktop
        // scripting debugAction
        cfg_widthBudget = config.widthBudget;
        cfg_menuPolicy = config.menuPolicy;
        cfg_menuCompacted = config.menuCompacted;
        cfg_debugAction = config.debugAction;
    }

    // Defaults and Reset change the key from outside: the checks follow it. A click changes it from
    // the model, which already matches, so it is not read back.
    property bool editing: false
    onCfg_enabledCalendarPluginsChanged: {
        if (!editing) {
            providers.populateEnabledPluginsList(cfg_enabledCalendarPlugins);
        }
    }
    PlasmaCalendar.EventPluginsManager {
        id: providers
        Component.onCompleted: populateEnabledPluginsList(page.cfg_enabledCalendarPlugins)
    }
    ColumnLayout {
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18nc("@info", "Enable Calendar Events (PIM) for appointments from KOrganizer or Merkuro. Apply, then choose your calendars in the provider's settings page. If that provider is missing, install your distribution's KDE PIM add-ons.")
        }
        Repeater {
            model: providers.model
            delegate: QQC2.CheckDelegate {
                required property var model
                Layout.fillWidth: true
                text: model.display
                checked: model.checked
                Accessible.name: text
                onClicked: {
                    model.checked = checked;
                    page.editing = true;
                    page.cfg_enabledCalendarPlugins = providers.enabledPlugins;
                    page.editing = false;
                    // The click replaced the binding: follow the model again.
                    checked = Qt.binding(() => model.checked);
                }
            }
        }
    }
}
