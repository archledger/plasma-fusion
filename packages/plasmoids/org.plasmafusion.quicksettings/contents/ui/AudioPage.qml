// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "components"
import "components/Icons.js" as Icons

// Audio output chooser opened from the chevron next to the volume slider.
ColumnLayout {
    id: page

    required property var backend
    required property FusionPalette pal
    required property FusionMetrics metrics
    property real listMaxHeight: metrics.px(230)

    signal back()

    readonly property Item firstFocusItem: header.backButton

    function portIcon(pulseObject) {
        if (!pulseObject || !pulseObject.ports || pulseObject.activePortIndex === undefined) {
            return Icons.speaker + Icons.wave1 + Icons.wave2;
        }
        const port = pulseObject.ports[pulseObject.activePortIndex];
        const name = port ? String(port.name || "") + String(port.description || "") : "";
        return /head(phone|set)/i.test(name) ? Icons.headphones : Icons.speaker + Icons.wave1 + Icons.wave2;
    }

    spacing: metrics.px(12)

    PageHeader {
        id: header
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        title: i18nc("@title", "Sound output")
        onBack: page.back()
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.min(contentHeight, page.listMaxHeight)
        Layout.maximumHeight: contentHeight
        visible: count > 0
        clip: true
        spacing: page.metrics.px(2)
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: page.backend.audio.sinkModel

        delegate: ListRow {
            required property var model
            required property int index

            width: ListView.view.width
            pal: page.pal
            metrics: page.metrics
            text: model.Description || model.Name || ""
            iconPath: page.portIcon(model.PulseObject)
            selected: !!(model.PulseObject && model.PulseObject.default)
            status: model.Muted ? i18nc("@info:status", "Muted") : ""
            trailingPath: selected ? Icons.check : ""
            onClicked: page.backend.audio.setDefault(model.PulseObject)
        }
    }

    FText {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: page.metrics.px(44)
        pal: page.pal
        metrics: page.metrics
        visible: !list.visible
        horizontalAlignment: Text.AlignHCenter
        color: page.pal.secondary
        text: i18nc("@info", "No output devices found")
    }

    Item {
        Layout.fillHeight: true
        visible: list.visible
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
            implicitHeight: page.metrics.px(32)
            radius: height / 2
            sidePadding: page.metrics.px(14)
            fill: page.pal.overlay(0.08)
            fontSize: 12.5
            iconPath: Icons.settingsSmall
            text: i18nc("@action:button", "Sound settings")
            onClicked: page.backend.audio.openSettings()
        }
    }
}
