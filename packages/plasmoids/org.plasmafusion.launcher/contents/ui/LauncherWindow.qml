/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami

// The launcher is its own frameless applet-popup window, placed by explicit position:
// centred horizontally on the screen and just above the dock, wherever the applet sits.
// Its background is the Plasma style's dialogs/background frame (translucent fill, 1 px edge,
// KWin blur through the frame mask); a "launcher-" prefixed frame is used when the style has one.
PlasmaCore.Dialog {
    id: window

    property var launcher
    property int cardWidth: 680
    property int cardHeight: 700
    // Text scale and pixel grid of this window (docs/parts/shell-launcher.md, "Text scale").
    readonly property alias metrics: fusionMetrics
    property var frameItem: null
    readonly property string framePrefix: frameItem && frameItem.usedPrefix !== undefined ? frameItem.usedPrefix : ""
    readonly property alias card: card

    type: PlasmaCore.Dialog.AppletPopup
    location: PlasmaCore.Types.Floating
    flags: Qt.WindowStaysOnTopHint
    hideOnWindowDeactivate: true
    backgroundHints: PlasmaCore.Dialog.StandardBackground

    // Corner radius of the frame: the width of its top-left corner element.
    property int frameRevision: 0
    readonly property KSvg.Svg frameSvg: KSvg.Svg {
        imagePath: "dialogs/background"
        onRepaintNeeded: window.frameRevision++
    }
    readonly property real cornerRadius: {
        const element = (window.framePrefix.length > 0 ? window.framePrefix + "-" : "") + "topleft";
        if (window.frameRevision >= 0 && window.frameSvg.hasElement(element)) {
            return window.frameSvg.elementSize(element).width;
        }
        return 12;
    }

    mainItem: Item {
        id: holder

        readonly property real ml: window.margins.left
        readonly property real mt: window.margins.top
        readonly property real mr: window.margins.right
        readonly property real mb: window.margins.bottom

        width: window.cardWidth - ml - mr
        height: window.cardHeight - mt - mb
        Layout.minimumWidth: width
        Layout.maximumWidth: width
        Layout.preferredWidth: width
        Layout.minimumHeight: height
        Layout.maximumHeight: height
        Layout.preferredHeight: height

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        FusionMetrics {
            id: fusionMetrics
            area: window.launcher ? window.launcher.availableScreenRect : Qt.rect(0, 0, 1440, 900)
        }

        FusionColors {
            id: colors
            dark: {
                const c = Kirigami.Theme.backgroundColor;
                return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
            }
            accent: Kirigami.Theme.highlightColor
        }

        LauncherCard {
            id: card
            x: -holder.ml
            y: -holder.mt
            width: window.cardWidth
            height: window.cardHeight
            focus: true
            launcher: window.launcher
            pal: colors
            metrics: fusionMetrics
            cornerRadius: window.cornerRadius
        }
    }

    // Use the style's "launcher" frame (radius 26 in Plasma Fusion) when it exists. The frame
    // item is created by the Dialog itself; if its structure ever changes nothing happens and
    // the regular dialog frame stays.
    function applyLauncherFrame() {
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
                if (candidate.imagePath !== undefined && candidate.prefix !== undefined && candidate.usedPrefix !== undefined) {
                    candidate.prefix = ["launcher", ""];
                    frameItem = candidate;
                    return;
                }
            }
        }
    }

    Component.onCompleted: applyLauncherFrame()
}
