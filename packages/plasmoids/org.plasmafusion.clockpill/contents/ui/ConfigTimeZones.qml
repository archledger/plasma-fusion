// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.private.digitalclock
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

KCM.ScrollViewKCM {
    id: page
    property alias cfg_selectedTimeZones: zones.selectedTimeZones
    property var cfg_selectedTimeZonesDefault: ["Local"]
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
    property int cfg_firstDayOfWeek: -1
    property var cfg_enabledCalendarPlugins: []
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
    property int cfg_firstDayOfWeekDefault
    property var cfg_enabledCalendarPluginsDefault: []
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
        // edited on the Calendar page
        cfg_enabledCalendarPlugins = config.enabledCalendarPlugins;
        // no control in the dialog; the width budget writes menuCompacted itself, desktop
        // scripting debugAction
        cfg_widthBudget = config.widthBudget;
        cfg_menuPolicy = config.menuPolicy;
        cfg_menuCompacted = config.menuCompacted;
        cfg_debugAction = config.debugAction;
    }

    TimeZoneModel {
        id: zones
        onSelectedTimeZonesChanged: if (selectedTimeZones.length === 0) { selectLocalTimeZone(); }
    }
    header: QQC2.TextField {
        id: search
        placeholderText: i18nc("@info:placeholder", "Search cities or regions")
        Accessible.name: i18nc("@label:textbox", "Search time zones")
    }
    view: ListView {
        clip: true
        model: TimeZoneFilterProxy {
            sourceModel: zones
            filterString: search.text
        }
        delegate: QQC2.CheckDelegate {
            required property var model
            width: ListView.view.width
            text: model.city + (model.region ? " · " + model.region : "")
            checked: model.checked
            Accessible.name: text
            onClicked: model.checked = checked
        }
    }
}
