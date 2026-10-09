// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import "components"
import "components/Icons.js" as Icons

// Audio output chooser opened from the chevron next to the volume slider.
ColumnLayout {
    id: page

    required property var backend
    required property FusionPalette pal
    required property FusionMetrics metrics
    property real listMaxHeight: metrics.px(230)
    property int initialTab: 0

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
        title: i18nc("@title", "Sound")
        onBack: page.back()
    }
    QQC2.TabBar {
        id: tabs
        Layout.fillWidth: true
        currentIndex: page.initialTab
        QQC2.TabButton { text: i18nc("@title:tab", "Output") }
        QQC2.TabButton { text: i18nc("@title:tab", "Input") }
        QQC2.TabButton { text: i18nc("@title:tab", "Applications") }
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.min(contentHeight, page.listMaxHeight)
        Layout.maximumHeight: contentHeight
        visible: tabs.currentIndex !== 2 && count > 0
        clip: true
        spacing: page.metrics.px(2)
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: tabs.currentIndex === 1 ? page.backend.audio.sourceModel : page.backend.audio.sinkModel

        delegate: ListRow {
            id: deviceRow
            required property var model
            required property int index

            width: ListView.view.width
            // The stock Audio Volume widget's device menu: ports (speakers, headphones) and the
            // card's profiles (HDMI, analog, Pro Audio, off), from plasma-pa's QML module in its
            // own file: without that module the row has no menu and the page still lists the
            // devices (AudioDeviceMenu.qml).
            hasMenu: deviceMenu.item ? deviceMenu.item.hasContent : false
            menuText: i18nc("@action:button", "Ports and profiles")
            onMenuRequested: from => {
                if (deviceMenu.item) {
                    deviceMenu.item.visualParent = from;
                    deviceMenu.item.openRelative();
                }
            }
            Loader {
                id: deviceMenu
                source: "AudioDeviceMenu.qml"
                onLoaded: {
                    item.pulseObject = Qt.binding(() => deviceRow.model.PulseObject);
                    item.cardModel = Qt.binding(() => page.backend.audio.cardModel);
                    item.input = Qt.binding(() => tabs.currentIndex === 1);
                    item.sourceModel = Qt.binding(() => tabs.currentIndex === 1 ? page.backend.audio.sourceModel : page.backend.audio.sinkModel);
                }
            }
            pal: page.pal
            metrics: page.metrics
            text: model.Description || model.Name || ""
            iconPath: tabs.currentIndex === 1 ? Icons.microphone : page.portIcon(model.PulseObject)
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
        visible: tabs.currentIndex !== 2 && list.count === 0
        horizontalAlignment: Text.AlignHCenter
        color: page.pal.secondary
        text: tabs.currentIndex === 1 ? i18nc("@info", "No input devices found") : i18nc("@info", "No output devices found")
    }
    AudioStreams {
        Layout.fillWidth: true
        visible: tabs.currentIndex === 2
        backend: page.backend
        pal: page.pal
        metrics: page.metrics
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
