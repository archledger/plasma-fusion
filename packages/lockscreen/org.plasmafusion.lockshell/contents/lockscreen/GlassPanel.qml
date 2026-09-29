// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami

// A frosted glass surface from the Lock board: the blurred wallpaper under a dark translucent
// fill with a thin light border (CSS: backdrop-filter blur(24px), rgba(14,18,34,.6), 1 px
// rgba(255,255,255,.1)). Without effects (software rendering) the fill gets more opaque instead.
Item {
    id: panel

    property Backdrop backdrop: null
    property real radius: 16
    property color fill: PfStyle.glassFill
    property color borderColor: PfStyle.glassBorder
    property real borderWidth: 1

    readonly property Item glassSource: backdrop ? backdrop.glassSource : null

    // Where this panel lies on the blurred wallpaper, in the wallpaper item's own coordinates
    // (the backdrop zooms around its centre while the prompt is shown).
    readonly property rect glassRect: {
        void (panel.x + panel.y + panel.width + panel.height);
        let p = panel.parent;
        for (let i = 0; i < 4 && p; ++i) {
            void (p.x + p.y);
            p = p.parent;
        }
        if (!panel.backdrop || !panel.glassSource) {
            return Qt.rect(0, 0, 0, 0);
        }
        const b = panel.backdrop;
        const z = b.zoom;
        const cx = b.width / 2;
        const cy = b.height / 2;
        const tl = panel.mapToItem(b, 0, 0);
        return Qt.rect(cx + (tl.x - cx) / z, cy + (tl.y - cy) / z, panel.width / z, panel.height / z);
    }

    ShaderEffectSource {
        id: glassTexture
        width: 1
        height: 1
        visible: false
        sourceItem: panel.glassSource
        sourceRect: panel.glassRect
        hideSource: false
        live: true
    }

    Kirigami.ShadowedTexture {
        anchors.fill: parent
        visible: panel.glassSource !== null && panel.width > 0 && panel.height > 0
        radius: panel.radius
        color: "transparent"
        source: panel.glassSource !== null ? glassTexture : null
    }

    Kirigami.ShadowedRectangle {
        anchors.fill: parent
        visible: panel.glassSource !== null
        radius: panel.radius
        color: panel.backdrop ? panel.backdrop.dimColor : "transparent"
    }

    Kirigami.ShadowedRectangle {
        anchors.fill: parent
        radius: panel.radius
        color: panel.glassSource !== null ? panel.fill
                                          : Qt.rgba(panel.fill.r, panel.fill.g, panel.fill.b, Math.min(1, panel.fill.a + 0.18))
    }

    // The edge goes over the fill, as a CSS border does over its background. (A bordered
    // ShadowedRectangle leaves the fill out under the border, which puts the light edge
    // straight on the blurred wallpaper and makes it far brighter than on the boards.)
    Rectangle {
        anchors.fill: parent
        radius: panel.radius
        antialiasing: true
        color: "transparent"
        border.width: panel.borderWidth
        border.color: panel.borderColor
    }
}
