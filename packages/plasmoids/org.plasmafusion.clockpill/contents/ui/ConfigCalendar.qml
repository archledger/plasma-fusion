// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.workspace.calendar as PlasmaCalendar

KCM.SimpleKCM {
    id: page
    property var cfg_enabledCalendarPlugins: []
    property var cfg_enabledCalendarPluginsDefault: []
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
