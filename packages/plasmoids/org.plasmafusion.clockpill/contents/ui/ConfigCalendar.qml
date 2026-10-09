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
                    page.cfg_enabledCalendarPlugins = providers.enabledPlugins;
                }
            }
        }
    }
}
