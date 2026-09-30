/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin
import org.kde.plasma.core as PlasmaCore

// The Meta+Z flyout (QuickSettings board "Snap layouts"): 280 px wide, padding 12, radius 16,
// "Snap layouts" + "Meta+Z", four 58 px layout cards (radius 9, padding 5, zones radius 4 with
// 4 px gaps) and "Or drag the window to a screen edge". Placed under the title bar, centred on
// the maximize button, as on the board.
//
// It is a popup: Esc, a click outside or any focus change closes it. It also closes itself
// after 30 s without input. The whole card follows the user's text size (it is sized before
// it is shown, so the scale comes from the window's output); radii and zone gaps do not.
PlasmaCore.Dialog {
    id: flyout

    readonly property FusionPalette pal: palette_
    property var target: null
    property var layouts: []
    property var frameItem: null

    // Keyboard focus and pointer hover, as (layout, zone).
    property int focusLayout: 0
    property int focusZone: 0
    property int hoverLayout: -1
    property int hoverZone: -1
    property bool keyboardUsed: false
    readonly property int activeLayout: hoverLayout >= 0 ? hoverLayout : focusLayout
    readonly property int activeZone: hoverLayout >= 0 ? hoverZone : focusZone

    // Text scale and pixel grid (docs/parts/kwin.md, "Text scale").
    readonly property alias metrics: fusionMetrics
    readonly property real pad: metrics.px(12) + 1 // 12 + the 1 px edge

    signal preview(int layoutIndex, int zoneIndex)
    signal chosen(int layoutIndex, int zoneIndex)
    signal dismissed()

    readonly property int cardWidth: metrics.windowSize(metrics.px(280))
    readonly property int cardHeight: Math.ceil(column.implicitHeight) + 2 * pad
    readonly property real marginLeft: margins.left
    readonly property real marginTop: margins.top
    readonly property real marginRight: margins.right
    readonly property real marginBottom: margins.bottom

    location: PlasmaCore.Types.Floating
    flags: Qt.Popup | Qt.X11BypassWindowManagerHint
    title: i18nd("plasmafusion", "Snap layouts")

    // Centred on the maximize button (the right one of a 28 px button pair 10 px from the
    // edge, 6 px apart: its centre is 58 px from the right edge) and hanging from the title bar.
    readonly property rect anchorRect: {
        const f = target ? target.frameGeometry : Qt.rect(0, 0, 0, 0);
        const c = target ? target.clientGeometry : f;
        const titleHeight = Math.max(0, c.y - f.y);
        return Qt.rect(f.x, f.y, f.width, titleHeight);
    }
    readonly property rect screenArea: target ? Workspace.clientArea(Workspace.MaximizeArea, target) : Qt.rect(0, 0, 1920, 1080)
    x: Math.round(Math.max(screenArea.x + 8, Math.min(screenArea.x + screenArea.width - cardWidth - 8,
                  anchorRect.x + anchorRect.width - 59 - cardWidth / 2)))
    y: Math.round(Math.max(screenArea.y + 8, Math.min(screenArea.y + screenArea.height - cardHeight - 8,
                  anchorRect.y + (anchorRect.height > 0 ? anchorRect.height : 8))))
    visible: false

    onVisibleChanged: {
        if (!visible) {
            dismissed();
        }
    }
    onActiveLayoutChanged: sendPreview()
    onActiveZoneChanged: sendPreview()

    function sendPreview() {
        if (hoverLayout >= 0 || keyboardUsed) {
            preview(activeLayout, activeZone);
        } else {
            preview(-1, -1);
        }
    }

    function zoneCount(layout) {
        return layouts[layout] ? layouts[layout].zones.length : 0;
    }

    function moveFocus(dLayout, dZone) {
        keyboardUsed = true;
        hoverLayout = -1;
        if (dZone !== 0) {
            let zone = focusZone + dZone;
            let layout = focusLayout;
            if (zone < 0) {
                layout = (layout + layouts.length - 1) % layouts.length;
                zone = zoneCount(layout) - 1;
            } else if (zone >= zoneCount(layout)) {
                layout = (layout + 1) % layouts.length;
                zone = 0;
            }
            focusLayout = layout;
            focusZone = zone;
        } else if (dLayout !== 0) {
            const layout = (focusLayout + dLayout + layouts.length) % layouts.length;
            focusZone = Math.min(focusZone, zoneCount(layout) - 1);
            focusLayout = layout;
        }
        idle.restart();
        sendPreview();
    }

    // Use a "snaplayouts" frame (board: radius 16, fill .90) when the Plasma style has one, else
    // its "notification" frame (radius 18, fill .90), else the regular dialog frame.
    function useFlyoutFrame() {
        if (frameItem || !contentItem) {
            return;
        }
        const children = contentItem.children;
        for (let i = 0; i < children.length; ++i) {
            const background = children[i];
            if (background === mainItem) {
                continue;
            }
            const inner = background.children;
            for (let j = 0; j < inner.length; ++j) {
                const candidate = inner[j];
                if (candidate.imagePath !== undefined && candidate.prefix !== undefined
                        && candidate.usedPrefix !== undefined) {
                    candidate.prefix = ["snaplayouts", "notification", ""];
                    frameItem = candidate;
                    return;
                }
            }
        }
    }

    Component.onCompleted: {
        useFlyoutFrame();
        visible = true;
        requestActivate();
    }

    onSceneGraphError: () => {
        // Intentionally empty: QtQuick would otherwise qFatal() on a graphics reset.
    }

    mainItem: FocusScope {
        id: scope
        focus: true
        width: flyout.cardWidth - flyout.marginLeft - flyout.marginRight
        height: flyout.cardHeight - flyout.marginTop - flyout.marginBottom

        FusionPalette {
            id: palette_
        }
        FusionMetrics {
            id: fusionMetrics
            screenScale: flyout.target && flyout.target.output ? flyout.target.output.devicePixelRatio : 0
            area: flyout.screenArea
        }

        Timer {
            id: idle
            interval: 30000
            running: true
            onTriggered: flyout.dismissed()
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape:
                flyout.dismissed();
                break;
            case Qt.Key_Left:
                flyout.moveFocus(0, -1);
                break;
            case Qt.Key_Right:
            case Qt.Key_Tab:
                flyout.moveFocus(0, 1);
                break;
            case Qt.Key_Backtab:
                flyout.moveFocus(0, -1);
                break;
            case Qt.Key_Up:
                flyout.moveFocus(-2, 0);
                break;
            case Qt.Key_Down:
                flyout.moveFocus(2, 0);
                break;
            case Qt.Key_1:
            case Qt.Key_2:
            case Qt.Key_3:
            case Qt.Key_4:
                flyout.focusLayout = event.key - Qt.Key_1;
                flyout.focusZone = 0;
                flyout.moveFocus(0, 0);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                flyout.chosen(flyout.activeLayout, flyout.activeZone);
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        Item {
            x: -flyout.marginLeft
            y: -flyout.marginTop
            width: flyout.cardWidth
            height: flyout.cardHeight

            Column {
                id: column
                x: flyout.pad
                y: flyout.pad
                width: parent.width - 2 * flyout.pad
                spacing: flyout.metrics.px(10)

                Item {
                    width: parent.width
                    height: heading.implicitHeight

                    Text {
                        id: heading
                        text: i18nd("plasmafusion", "Snap layouts")
                        font.family: flyout.metrics.family
                        font.pointSize: flyout.metrics.font(12) * 0.75
                        font.weight: Font.ExtraBold
                        color: flyout.pal.heading
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: heading.verticalCenter
                        text: "Meta+Z"
                        font.family: flyout.metrics.family
                        font.pointSize: flyout.metrics.font(11) * 0.75
                        color: flyout.pal.shortcut
                    }
                }

                Grid {
                    id: cards
                    columns: 2
                    spacing: flyout.metrics.px(10)

                    Repeater {
                        model: flyout.layouts.length
                        delegate: Rectangle {
                            id: card
                            required property int index
                            readonly property var layout: flyout.layouts[index]
                            width: (column.width - cards.spacing) / 2
                            height: flyout.metrics.px(58)
                            radius: 9
                            color: flyout.pal.cardFill

                            Accessible.role: Accessible.Grouping
                            Accessible.name: [i18nd("plasmafusion", "Two halves"), i18nd("plasmafusion", "Two thirds and one third"),
                                              i18nd("plasmafusion", "Quarters"), i18nd("plasmafusion", "Three columns")][index] || ""

                            Item {
                                id: inner
                                x: 5
                                y: 5
                                width: card.width - 10
                                height: card.height - 10

                                Repeater {
                                    model: card.layout.zones.length
                                    delegate: Rectangle {
                                        id: zone
                                        required property int index
                                        readonly property var fraction: card.layout.zones[index]
                                        readonly property bool active: flyout.activeLayout === card.index && flyout.activeZone === index
                                        x: Math.round(fraction[0] * (inner.width + 4))
                                        y: Math.round(fraction[1] * (inner.height + 4))
                                        width: Math.round((fraction[0] + fraction[2]) * (inner.width + 4) - 4) - x
                                        height: Math.round((fraction[1] + fraction[3]) * (inner.height + 4) - 4) - y
                                        radius: 4
                                        color: active ? flyout.pal.zone : (zoneArea.containsMouse ? flyout.pal.hoverFill : flyout.pal.zoneFill)

                                        Accessible.role: Accessible.Button
                                        Accessible.name: card.Accessible.name + " " + (index + 1)

                                        MouseArea {
                                            id: zoneArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onEntered: {
                                                flyout.hoverLayout = card.index;
                                                flyout.hoverZone = zone.index;
                                                idle.restart();
                                            }
                                            onExited: {
                                                if (flyout.hoverLayout === card.index && flyout.hoverZone === zone.index) {
                                                    flyout.hoverLayout = -1;
                                                    flyout.hoverZone = -1;
                                                }
                                            }
                                            onClicked: flyout.chosen(card.index, zone.index)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: i18nd("plasmafusion", "Or drag the window to a screen edge")
                    elide: Text.ElideRight
                    font.family: flyout.metrics.family
                    font.pointSize: flyout.metrics.font(11.5) * 0.75
                    color: flyout.pal.muted
                }
            }
        }
    }
}
