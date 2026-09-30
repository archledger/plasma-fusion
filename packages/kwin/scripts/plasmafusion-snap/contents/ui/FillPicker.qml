/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Window
import org.kde.kwin

// "Pick a window for this side" (TabsSnap board, "Fill the other half"): covers the empty
// half with the blurred wallpaper under a tint (rgba(8,11,24,.55) on dark) and offers the other
// windows of the workspace as cards. A popup: Esc, a click elsewhere or any focus change
// dismisses it; it also closes itself after a minute without input. The heading and the card
// captions follow the user's text size.
Window {
    id: picker

    readonly property FusionPalette pal: palette_
    property rect area
    property var candidates: []
    property var output: null
    property var desktop: null
    property int current: 0

    // Text scale and pixel grid of this window (docs/parts/kwin.md, "Text scale").
    readonly property alias metrics: fusionMetrics
    readonly property int pad: 24
    readonly property int spacing: 12
    readonly property int columns: {
        const room = width - 2 * pad + spacing;
        const fit = Math.max(1, Math.floor(room / (180 + spacing)));
        return Math.max(1, Math.min(candidates.length <= 4 ? 2 : 3, fit));
    }
    readonly property real cardWidth: (width - 2 * pad - (columns - 1) * spacing) / columns
    readonly property real thumbHeight: Math.min(220, Math.round(cardWidth * 0.62))

    signal picked(var win)
    signal dismissed()

    flags: Qt.Popup | Qt.FramelessWindowHint | Qt.BypassWindowManagerHint
    color: "transparent"
    title: i18nd("plasmafusion", "Pick a window for this side")
    x: area.x
    y: area.y
    width: Math.max(240, area.width)
    height: Math.max(200, area.height)
    visible: false

    onVisibleChanged: {
        if (!visible) {
            dismissed();
        }
    }

    Component.onCompleted: {
        visible = true;
        requestActivate();
    }

    function move(delta) {
        if (candidates.length === 0) {
            return;
        }
        current = (current + delta + candidates.length) % candidates.length;
        idle.restart();
        ensureVisible();
    }

    // Keeps the selected card in view when there are more windows than fit (keyboard).
    function ensureVisible() {
        const item = cardRepeater.itemAt(current);
        if (!item || flick.contentHeight <= flick.height) {
            return;
        }
        if (item.y < flick.contentY) {
            flick.contentY = item.y;
        } else if (item.y + item.height > flick.contentY + flick.height) {
            flick.contentY = Math.min(flick.contentHeight - flick.height, item.y + item.height - flick.height);
        }
    }

    FusionMetrics {
        id: fusionMetrics
        area: picker.area
    }

    FusionPalette {
        id: palette_
    }

    Timer {
        id: idle
        interval: 60000
        running: true
        onTriggered: picker.dismissed()
    }

    // Frosted backdrop: the wallpaper of this screen and workspace, blurred, then the tint.
    Item {
        anchors.fill: parent
        clip: true

        DesktopBackground {
            id: wallpaper
            visible: picker.output !== null
            readonly property rect screen: picker.output ? picker.output.geometry : Qt.rect(picker.x, picker.y, picker.width, picker.height)
            output: picker.output
            desktop: picker.desktop
            activity: Workspace.currentActivity
            x: screen.x - picker.x
            y: screen.y - picker.y
            width: screen.width
            height: screen.height
        }

        MultiEffect {
            source: wallpaper
            x: wallpaper.x
            y: wallpaper.y
            width: wallpaper.width
            height: wallpaper.height
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            saturation: 0.1
            autoPaddingEnabled: false
        }
    }

    Rectangle {
        anchors.fill: parent
        color: picker.pal.pickerFill
    }

    FocusScope {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape:
                picker.dismissed();
                break;
            case Qt.Key_Left:
            case Qt.Key_Backtab:
                picker.move(-1);
                break;
            case Qt.Key_Right:
            case Qt.Key_Tab:
                picker.move(1);
                break;
            case Qt.Key_Up:
                picker.move(-picker.columns);
                break;
            case Qt.Key_Down:
                picker.move(picker.columns);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                if (picker.candidates.length > 0) {
                    picker.picked(picker.candidates[picker.current]);
                }
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        // A click on the tint (not on a card) dismisses, like a click outside.
        MouseArea {
            anchors.fill: parent
            onClicked: picker.dismissed()
        }

        Text {
            id: heading
            x: picker.pad
            y: picker.pad
            width: parent.width - 2 * picker.pad
            text: i18nd("plasmafusion", "Pick a window for this side")
            elide: Text.ElideRight
            font.family: picker.metrics.family
            font.pointSize: picker.metrics.font(14) * 0.75
            font.weight: Font.ExtraBold
            color: picker.pal.pickerHeading
        }

        Flickable {
            id: flick
            x: picker.pad
            y: heading.y + heading.height + picker.metrics.px(14)
            width: parent.width - 2 * picker.pad
            height: parent.height - y - picker.pad
            contentWidth: width
            contentHeight: grid.height
            clip: contentHeight > height
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Grid {
                id: grid
                columns: picker.columns
                spacing: picker.spacing

                Repeater {
                    id: cardRepeater
                    model: picker.candidates
                    delegate: PickerCard {
                        required property int index
                        required property var modelData
                        width: picker.cardWidth
                        thumbnailHeight: picker.thumbHeight
                        pal: picker.pal
                        metrics: picker.metrics
                        window: modelData
                        selected: index === picker.current
                        onHoveredChanged: {
                            if (hovered) {
                                picker.current = index;
                                idle.restart();
                            }
                        }
                        onActivated: picker.picked(modelData)
                    }
                }
            }
        }
    }
}
