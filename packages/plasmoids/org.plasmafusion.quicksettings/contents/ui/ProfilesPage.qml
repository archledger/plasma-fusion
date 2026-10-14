// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "components"
import "components/Icons.js" as Icons

// Power mode chooser (the Power mode tile's chevron, P7): the daemon's profiles with the active one
// marked, as the stock Power and Battery widget offers them. Performance stays listed while the
// daemon inhibits it, but cannot be chosen, and the reason shows under the list with the
// applications holding a profile.
ColumnLayout {
    id: page
    required property var backend
    required property FusionPalette pal
    required property FusionMetrics metrics
    signal back()
    readonly property Item firstFocusItem: header.backButton
    spacing: metrics.px(12)

    function icon(profile: string): string {
        switch (profile) {
        case "power-saver":
            return Icons.gaugeLow;
        case "performance":
            return Icons.gauge;
        default:
            return Icons.gaugeMid;
        }
    }

    PageHeader {
        id: header
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        title: i18nc("@title", "Power mode")
        onBack: page.back()
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: page.metrics.px(2)
        Repeater {
            model: page.backend.profile.options
            delegate: ListRow {
                id: profileRow
                required property var modelData
                objectName: "profile-" + modelData.profile
                Layout.fillWidth: true
                pal: page.pal
                metrics: page.metrics
                text: page.backend.profile.profileName(modelData.profile)
                iconPath: page.icon(modelData.profile)
                selected: modelData.active
                enabled: modelData.enabled
                opacity: enabled ? 1 : 0.55
                status: !modelData.enabled ? i18nc("@info:status power profile that cannot be chosen now", "Unavailable")
                      : page.backend.profile.failedProfile === modelData.profile ? i18nc("@info:status a power profile switch was refused", "Couldn't switch")
                      : ""
                trailingPath: modelData.active ? Icons.check : ""
                Accessible.role: Accessible.RadioButton
                Accessible.checkable: true
                Accessible.checked: modelData.active
                Accessible.description: modelData.enabled ? status : page.backend.profile.inhibitionNote
                onClicked: page.backend.profile.setProfile(modelData.profile)
            }
        }
    }
    FText {
        objectName: "profile-note"
        Layout.fillWidth: true
        Layout.leftMargin: page.metrics.px(10)
        Layout.rightMargin: page.metrics.px(10)
        visible: text !== ""
        pal: page.pal
        metrics: page.metrics
        px: 11.5
        color: page.pal.secondary
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        text: page.backend.profile.note
    }
    Item {
        Layout.fillHeight: true
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: page.pal.overlay(0.08)
    }
    RowLayout {
        Layout.fillWidth: true
        Item {
            Layout.fillWidth: true
        }
        TextButton {
            pal: page.pal
            metrics: page.metrics
            targetHeight: page.metrics.px(32)
            radius: height / 2
            sidePadding: page.metrics.px(14)
            fill: page.pal.overlay(0.08)
            fontSize: 12.5
            iconPath: Icons.settingsSmall
            text: i18nc("@action:button", "Power settings")
            onClicked: page.backend.profile.openSettings()
        }
    }
}
