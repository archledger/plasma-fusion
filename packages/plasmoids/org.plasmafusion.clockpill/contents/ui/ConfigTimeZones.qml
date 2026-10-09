// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.private.digitalclock
import org.kde.kcmutils as KCM

KCM.ScrollViewKCM {
    id: page
    property alias cfg_selectedTimeZones: zones.selectedTimeZones
    property var cfg_selectedTimeZonesDefault: ["Local"]
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
