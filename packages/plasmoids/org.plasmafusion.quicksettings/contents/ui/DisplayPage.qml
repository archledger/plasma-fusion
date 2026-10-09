// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import "components"
import "components/Icons.js" as Icons

// Brightness (the brightness slider's chevron): a slider for every display PowerDevil can dim
// (internal panels and monitors over DDC/CI) and the keyboard backlight, as the stock Brightness
// widget lists them. The main sheet's slider is the first display's.
ColumnLayout {
    id: page
    required property var backend
    required property FusionPalette pal
    required property FusionMetrics metrics
    signal back()
    readonly property Item firstFocusItem: header.backButton
    spacing: metrics.px(12)

    PageHeader {
        id: header
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        title: i18nc("@title", "Brightness")
        onBack: page.back()
    }

    Repeater {
        model: page.backend.display.displaysModel
        delegate: ColumnLayout {
            id: displayRow
            required property string displayName
            required property string label
            required property int brightness
            required property int maxBrightness
            Layout.fillWidth: true
            spacing: page.metrics.px(4)
            visible: maxBrightness > 0

            FText {
                Layout.fillWidth: true
                pal: page.pal
                metrics: page.metrics
                text: displayRow.label || displayRow.displayName
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                LineIcon {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    size: 18
                    path: Icons.brightness
                    color: page.pal.controlText
                }
                FusionSlider {
                    id: displaySlider
                    Layout.fillWidth: true
                    pal: page.pal
                    from: 0.01
                    Accessible.name: i18nc("@label:slider %1 display name", "Brightness of %1", displayRow.label || displayRow.displayName)
                    value: displayRow.maxBrightness > 0 ? displayRow.brightness / displayRow.maxBrightness : 0
                    onMoved: page.backend.display.setDisplayBrightness(displayRow.displayName,
                                                                      Math.max(1, Math.round(value * displayRow.maxBrightness)))
                    onDraggingChanged: {
                        if (!dragging) {
                            value = Qt.binding(() => displayRow.maxBrightness > 0 ? displayRow.brightness / displayRow.maxBrightness : 0);
                        }
                    }
                }
                FText {
                    Layout.preferredWidth: page.metrics.px(40)
                    pal: page.pal
                    metrics: page.metrics
                    horizontalAlignment: Text.AlignRight
                    color: page.pal.secondary
                    text: i18nc("@info brightness percentage", "%1%", Math.round(displaySlider.value * 100))
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: page.backend.display.keyboardAvailable
        spacing: page.metrics.px(4)

        FText {
            Layout.fillWidth: true
            pal: page.pal
            metrics: page.metrics
            text: i18nc("@label", "Keyboard backlight")
            font.weight: Font.Bold
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            LineIcon {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                size: 18
                path: Icons.keyboard
                color: page.pal.controlText
            }
            // Keyboard lights have a few levels (often 0-2 or 0-3): the slider steps through them.
            FusionSlider {
                id: keyboardSlider
                Layout.fillWidth: true
                pal: page.pal
                from: 0
                to: Math.max(1, page.backend.display.keyboardMax)
                stepSize: 1
                snapMode: T.Slider.SnapAlways
                Accessible.name: i18nc("@label:slider", "Keyboard backlight")
                value: page.backend.display.keyboardValue
                onMoved: page.backend.display.setKeyboardBrightness(Math.round(value))
                onDraggingChanged: {
                    if (!dragging) {
                        value = Qt.binding(() => page.backend.display.keyboardValue);
                    }
                }
            }
            FText {
                Layout.preferredWidth: page.metrics.px(40)
                pal: page.pal
                metrics: page.metrics
                horizontalAlignment: Text.AlignRight
                color: page.pal.secondary
                text: Math.round(keyboardSlider.value) === 0 ? i18nc("@info keyboard backlight", "Off")
                    : i18nc("@info brightness percentage", "%1%", Math.round(keyboardSlider.value / keyboardSlider.to * 100))
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
