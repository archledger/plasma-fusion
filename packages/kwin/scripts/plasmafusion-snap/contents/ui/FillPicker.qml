/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
// KWin 6.8 names its window class "Window" in org.kde.kwin (uncreatable), which shadows
// QtQuick's Window after the unqualified import below; create QtQuick's by its own name.
import QtQuick.Window as QtQuickWindow
import org.kde.kwin

// "Pick a window for this side" (TabsSnap board, "Fill the other half"): covers the empty
// half with the Tinted material (EFFECTS 3.2: one blurred capture of this screen's wallpaper,
// taken when the picker opens, under the tint; no live blur) and offers the other windows of the
// workspace as cards. In tablet posture the cards are wider and taller (TABLET 4.10). A popup:
// Esc, a click elsewhere or any focus change dismisses it; it also closes itself after a minute
// without input. The heading and the card captions follow the user's text size.
QtQuickWindow.Window {
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
    // Tablet posture (TABLET 4.10): cards clamp(W / 5, 220, 300) wide, thumbnails 0.6 x width.
    readonly property bool tablet: tabletState.tablet
    readonly property real tabletCard: Math.max(220, Math.min(300, (output ? output.geometry.width : width) / 5))
    readonly property int columns: {
        const room = width - 2 * pad + spacing;
        if (tablet) {
            return Math.max(1, Math.floor(room / (tabletCard + spacing)));
        }
        const fit = Math.max(1, Math.floor(room / (180 + spacing)));
        return Math.max(1, Math.min(candidates.length <= 4 ? 2 : 3, fit));
    }
    readonly property real cardWidth: tablet ? Math.min(300, (width - 2 * pad - (columns - 1) * spacing) / columns)
                                             : (width - 2 * pad - (columns - 1) * spacing) / columns
    readonly property real thumbHeight: tablet ? Math.round(cardWidth * 0.6) : Math.min(220, Math.round(cardWidth * 0.62))

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

    FusionTablet {
        id: tabletState
    }
    FusionMetrics {
        id: fusionMetrics
        area: picker.area
        tablet: tabletState.tablet
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

    // The backdrop: the wallpaper of this screen and workspace, captured once into
    // FusionBackdrop's small blurred copy (the capture is taken again after the wallpaper item's
    // first frame, EFFECTS 6.4).
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
        FusionBackdrop {
            id: backdrop
            x: wallpaper.x
            y: wallpaper.y
            width: wallpaper.width
            height: wallpaper.height
            sourceItem: picker.output !== null ? wallpaper : null
            dark: picker.pal.dark
        }
    }
    property int framesSeen: 0
    onFrameSwapped: {
        if (framesSeen < 2 && ++framesSeen === 2) {
            backdrop.recapture();
        }
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
            // A pointer convenience (Esc dismisses too).
            Accessible.ignored: true
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
                        tablet: picker.tablet
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
