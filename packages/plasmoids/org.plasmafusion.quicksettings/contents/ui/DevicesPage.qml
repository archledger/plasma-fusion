// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

import "components"
import "components/Icons.js" as Icons
import "../code/devices.js" as DeviceList

// Disks & Devices drill-down (stock Disks & Devices): each removable device with its state and free
// space; the row opens it (the file manager for a volume, mounting it first), the trailing button
// safely removes a mounted volume or ejects a disc, or mounts a volume that is not mounted.
ColumnLayout {
    id: page

    required property var backend
    required property FusionPalette pal
    required property FusionMetrics metrics
    property real listMaxHeight: metrics.px(300)

    signal back()

    readonly property Item firstFocusItem: header.backButton

    spacing: metrics.px(12)
    Component.onCompleted: page.backend.devices.refresh()

    PageHeader {
        id: header
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        title: i18nc("@title", "Disks & Devices")
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
        spacing: page.metrics.px(6)
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: page.backend.devices.list

        delegate: ColumnLayout {
            id: device
            required property var modelData
            readonly property real usedFraction: DeviceList.used(modelData)

            width: ListView.view.width
            spacing: page.metrics.px(4)

            RowLayout {
                Layout.fillWidth: true
                spacing: page.metrics.px(6)

                T.AbstractButton {
                    id: openButton
                    Layout.fillWidth: true
                    implicitHeight: page.metrics.px(48)
                    focusPolicy: Qt.TabFocus
                    hoverEnabled: true
                    enabled: device.modelData.openPredicate !== "" && !device.modelData.busy
                    text: device.modelData.name
                    Accessible.role: Accessible.Button
                    Accessible.name: i18nc("@action:button %1 device name", "Open %1", device.modelData.name)
                    Accessible.description: status.text
                    Keys.onReturnPressed: clicked()
                    Keys.onEnterPressed: clicked()
                    onClicked: page.backend.devices.open(device.modelData.udi)

                    background: Rectangle {
                        radius: 10
                        color: openButton.down ? page.pal.overlay(0.1) : (openButton.hovered ? page.pal.overlay(0.06) : "transparent")
                        FocusRing {
                            anchors.margins: -2
                            baseRadius: 10
                            ringColor: page.pal.focus
                            shown: openButton.visualFocus
                        }
                    }
                    contentItem: RowLayout {
                        spacing: page.metrics.px(12)
                        Kirigami.Icon {
                            Layout.leftMargin: page.metrics.px(10)
                            Layout.preferredWidth: page.metrics.px(28)
                            Layout.preferredHeight: page.metrics.px(28)
                            source: device.modelData.icon
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            FText {
                                Layout.fillWidth: true
                                pal: page.pal
                                metrics: page.metrics
                                text: device.modelData.name
                                textFormat: Text.PlainText
                                font.weight: Font.Bold
                            }
                            FText {
                                id: status
                                Layout.fillWidth: true
                                pal: page.pal
                                metrics: page.metrics
                                px: 11.5
                                color: page.pal.secondary
                                textFormat: Text.PlainText
                                text: {
                                    const d = device.modelData;
                                    if (d.state === DeviceList.MOUNTING) {
                                        return i18nc("@info:status", "Mounting…");
                                    }
                                    if (d.state === DeviceList.UNMOUNTING) {
                                        return d.optical ? i18nc("@info:status", "Ejecting…") : i18nc("@info:status", "Removing…");
                                    }
                                    if (d.mounted && d.freeText !== "" && d.sizeText !== "") {
                                        return i18nc("@info:status %1 free space, %2 size", "%1 free of %2", d.freeText, d.sizeText);
                                    }
                                    if (d.mounted) {
                                        return i18nc("@info:status", "Mounted");
                                    }
                                    return d.mountable ? i18nc("@info:status", "Not mounted") : i18nc("@info:status", "Connected");
                                }
                            }
                        }
                    }
                }
                IconButton {
                    pal: page.pal
                    size: page.metrics.px(34)
                    iconSize: page.metrics.px(17)
                    visible: device.modelData.mountable || device.modelData.optical
                    enabled: !device.modelData.busy
                    // Mounted (or a disc): safely remove / eject; otherwise mount.
                    readonly property bool removes: device.modelData.mounted || device.modelData.optical
                    iconPath: removes ? Icons.eject : Icons.usbDrive
                    text: device.modelData.optical ? i18nc("@action:button", "Eject")
                        : removes ? i18nc("@action:button", "Safely remove")
                                  : i18nc("@action:button", "Mount")
                    onClicked: removes ? page.backend.devices.unmount(device.modelData.udi)
                                       : page.backend.devices.mount(device.modelData.udi)
                }
            }
            // Space in use on a mounted volume.
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: page.metrics.px(50)
                Layout.rightMargin: page.metrics.px(46)
                Layout.preferredHeight: page.metrics.px(4)
                visible: device.usedFraction >= 0
                radius: height / 2
                color: page.pal.overlay(0.1)
                Rectangle {
                    width: parent.width * Math.max(0, device.usedFraction)
                    height: parent.height
                    radius: parent.radius
                    color: device.usedFraction > 0.9 ? page.pal.warning : page.pal.accent
                }
            }
            // The engines' own message: why removing failed (and which applications hold the
            // device), or that it can now be safely removed.
            FText {
                Layout.fillWidth: true
                Layout.leftMargin: page.metrics.px(50)
                visible: device.modelData.message !== ""
                pal: page.pal
                metrics: page.metrics
                px: 11.5
                color: device.modelData.messageIsError ? page.pal.warning : page.pal.secondary
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: device.modelData.message
            }
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
        wrapMode: Text.WordWrap
        color: page.pal.secondary
        text: i18nc("@info", "No removable devices")
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
        spacing: page.metrics.px(8)
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
            text: i18nc("@action:button", "Removable storage settings")
            onClicked: page.backend.devices.openSettings()
        }
    }
}
