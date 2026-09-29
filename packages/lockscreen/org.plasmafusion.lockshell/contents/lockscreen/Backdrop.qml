// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import Qt5Compat.GraphicalEffects

// The wallpaper behind the lock screen.
//   factor 0: Lock board, the wallpaper as it is under a 22 % dim.
//   factor 1: Login board, the wallpaper blurred and zoomed by 8 % under a 50 % dim.
// glassSource is a blurred copy of the wallpaper that GlassPanel shows through its glass.
Item {
    id: backdrop

    // The greeter's wallpaper item (context property "wallpaper"); null when no wallpaper loaded.
    property Item source: null
    property real factor: 0

    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    readonly property bool effectsAvailable: source !== null && !softwareRendering
    readonly property real zoom: effectsAvailable ? 1 + 0.08 * factor : 1
    readonly property Item glassSource: effectsAvailable ? glassBlur : null
    // The dim over the wallpaper; glass panels put it over their blurred copy too, since the
    // board's backdrop blur sees the dimmed wallpaper.
    readonly property color dimColor: dim.color

    // Mean luminance (0..1) of the wallpaper's upper half, where the clock sits. The Lock board
    // is drawn for a dark wallpaper; a bright one (the light Plasma Fusion wallpaper, a photo)
    // gets extra dim so that the white clock and date stay readable. Dark wallpapers keep the
    // board's 22 %.
    property real brightness: 0
    readonly property real extraDim: Math.max(0, Math.min(0.3, (brightness - 0.4) * 0.9))
    // Dim opacity while idle (Lock board 22 %, plus the extra above) and while the prompt is
    // shown. The prompt's white name and clock and its #8f98b3 placeholder are drawn for the
    // Login board's dark backdrop: its 50 % dim over the dark wallpaper leaves a mean
    // brightness of about 0.1. A brighter wallpaper gets as much dim as it takes to come down
    // to that level (at most 90 %); the dark Plasma Fusion wallpaper keeps exactly 50 %.
    readonly property real idleDim: PfStyle.dimIdle.a + extraDim
    readonly property real promptDim: {
        const target = 0.11; // mean brightness of the Login board's dimmed backdrop
        const dimLevel = 0.04; // brightness of the dim colour itself
        const needed = brightness > target ? (brightness - target) / (brightness - dimLevel) : 0;
        const board = PfStyle.dimActive.a + (effectsAvailable ? 0 : 0.1);
        return Math.min(0.9, Math.max(board, needed));
    }

    function measureBrightness() {
        if (!source || source.width < 1 || source.height < 1) {
            return;
        }
        source.grabToImage(result => {
            probe.grabUrl = result.url;
            probe.loadImage(result.url);
            // A grab is usually available at once, in which case imageLoaded is not emitted.
            if (probe.isImageLoaded(result.url)) {
                probe.requestPaint();
            }
        }, Qt.size(32, 20));
    }

    // A tiny canvas that reads the grabbed pixels (drawn at 1 % opacity: a canvas only paints
    // while it is visible).
    Canvas {
        id: probe
        property url grabUrl
        width: 32
        height: 20
        opacity: 0.01
        onImageLoaded: requestPaint()
        onPaint: {
            if (!isImageLoaded(grabUrl)) {
                return;
            }
            const ctx = getContext("2d");
            ctx.drawImage(grabUrl, 0, 0, 32, 20);
            const d = ctx.getImageData(0, 0, 32, 10).data;
            let sum = 0;
            for (let i = 0; i < d.length; i += 4) {
                sum += 0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2];
            }
            backdrop.brightness = sum / (d.length / 4) / 255;
            ctx.clearRect(0, 0, 32, 20);
            unloadImage(grabUrl);
        }
    }
    // Measure early (during the launch fade), twice more while the wallpaper may still be
    // loading, then now and then (slideshows, day/night images).
    Timer {
        property int runs: 0
        interval: 400
        running: backdrop.source !== null
        repeat: true
        onTriggered: {
            backdrop.measureBrightness();
            runs += 1;
            interval = runs < 3 ? 1000 : 60000;
        }
    }

    // Shown when there is no wallpaper at all (the board's night sky).
    Rectangle {
        anchors.fill: parent
        color: PfStyle.fallbackBackground
        visible: backdrop.source === null
    }

    // Always-blurred copy for the glass surfaces; rendered only into their textures.
    FastBlur {
        id: glassBlur
        anchors.fill: parent
        visible: false
        source: backdrop.effectsAvailable ? backdrop.source : null
        radius: 64
        cached: false
    }

    // The visible wallpaper: sharp while idle, blurred and zoomed while the prompt is shown.
    FastBlur {
        id: wallpaperBlur
        anchors.fill: parent
        visible: backdrop.effectsAvailable
        source: backdrop.effectsAvailable ? backdrop.source : null
        radius: 72 * backdrop.factor
        scale: backdrop.zoom
    }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: Qt.rgba(PfStyle.dimIdle.r + (PfStyle.dimActive.r - PfStyle.dimIdle.r) * backdrop.factor,
                       PfStyle.dimIdle.g + (PfStyle.dimActive.g - PfStyle.dimIdle.g) * backdrop.factor,
                       PfStyle.dimIdle.b + (PfStyle.dimActive.b - PfStyle.dimIdle.b) * backdrop.factor,
                       backdrop.idleDim + (backdrop.promptDim - backdrop.idleDim) * backdrop.factor)

        Behavior on color {
            enabled: backdrop.factor === 0 || backdrop.factor === 1
            ColorAnimation { duration: 400 }
        }
    }
}
