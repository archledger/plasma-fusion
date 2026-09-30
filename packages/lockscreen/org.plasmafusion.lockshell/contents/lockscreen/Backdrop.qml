// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Effects

// The wallpaper behind the lock screen.
//   factor 0: Lock board, the wallpaper as it is under a 22 % dim.
//   factor 1: Login board, the wallpaper blurred and zoomed by 8 % under a 50 % dim.
//
// The greeter draws its wallpaper item itself, under everything (z -1000). Nothing re-renders
// it here (EFFECTS.md 6.4): one small copy (1/8 size) is taken when the wallpaper is ready,
// when it changes and when the prompt opens, blurred once at that size into a cached layer, and
// the prompt cross-fades that layer in (opacity = factor, zoomed with it). glassSource, what
// GlassPanel shows through its glass, is the same cached layer. The blur radius follows the
// screen size (ADAPTIVE 5.10).
Item {
    id: backdrop

    // The greeter's wallpaper item (context property "wallpaper"); null when no wallpaper loaded.
    property Item source: null
    property real factor: 0

    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    readonly property bool effectsAvailable: source !== null && !softwareRendering
    readonly property real zoom: effectsAvailable ? 1 + 0.08 * factor : 1
    readonly property Item glassSource: effectsAvailable ? blurred : null
    // The dim over the wallpaper; glass panels put it over their blurred copy too, since the
    // board's backdrop blur sees the dimmed wallpaper.
    readonly property color dimColor: dim.color

    // Device pixels per logical pixel of this window (on Wayland at a fractional scale the
    // window's own ratio; Screen.devicePixelRatio is the output's whole buffer scale there).
    readonly property real dpr: {
        const w = Window.window;
        const r = w && w.devicePixelRatio > 0 ? w.devicePixelRatio : Screen.devicePixelRatio;
        return r > 0 ? r : 1;
    }
    // The board's 72 px blur at 1440 x 900, proportional to the screen (ADAPTIVE 5.10), in the
    // pixels of the 1/8 copy it runs on (logical; MultiEffect's blurMax, at most 64). For the
    // same number MultiEffect blurs less than the FastBlur the board was matched with (10-90 %
    // edge 56 against 90 device px on the ThinkPad), hence the 1.6.
    readonly property real copyScale: 1 / 8
    readonly property real blurPx: 72 * 1.6 * Math.min(width, height) / 900 * copyScale

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

    // Take the small copy (and the brightness) again: when the wallpaper is ready and whenever
    // it changes (GAPS G23: no timer while locked). A wallpaper plugin signals a new picture by
    // repainting; the copy is refreshed on its own `live: false` schedule only when asked.
    function refresh() {
        measureBrightness();
        copy.scheduleUpdate();
    }
    Timer {
        id: settle
        interval: 400
        onTriggered: backdrop.refresh()
    }
    onSourceChanged: settle.restart()
    Component.onCompleted: settle.restart()
    // The prompt opening takes the copy again (a slideshow may have moved on while locked): one
    // small copy and one blur per prompt, no timer.
    property bool promptRefreshed: false
    onFactorChanged: {
        if (factor > 0 && !promptRefreshed) {
            promptRefreshed = true;
            refresh();
        } else if (factor === 0) {
            promptRefreshed = false;
        }
    }
    Connections {
        target: backdrop.source
        ignoreUnknownSignals: true
        // org.kde.image and the slideshow plugin: a new image or a new slide.
        function onImageChanged() { settle.restart(); }
        function onSourceChanged() { settle.restart(); }
        function onWidthChanged() { settle.restart(); }
        function onHeightChanged() { settle.restart(); }
    }
    Connections {
        // qmllint disable missing-property
        target: backdrop.source ? backdrop.source.configuration || null : null
        // qmllint enable missing-property
        ignoreUnknownSignals: true
        function onImageChanged() { settle.restart(); }
        function onValueChanged() { settle.restart(); }
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

    // Shown when there is no wallpaper at all (the board's night sky).
    Rectangle {
        anchors.fill: parent
        color: PfStyle.fallbackBackground
        visible: backdrop.source === null
    }

    // The small copy of the wallpaper: rendered once (live: false) and again on refresh().
    ShaderEffectSource {
        id: copy
        width: 1
        height: 1
        visible: false
        sourceItem: backdrop.effectsAvailable ? backdrop.source : null
        textureSize: Qt.size(Math.max(1, Math.round(backdrop.width * backdrop.copyScale * backdrop.dpr)),
                             Math.max(1, Math.round(backdrop.height * backdrop.copyScale * backdrop.dpr)))
        live: false
        hideSource: false
        smooth: true
    }

    // The blurred copy, shown with the prompt: faded in by `factor` and zoomed with it. Glass
    // panels sample it through their own ShaderEffectSource also while it is hidden (idle).
    Item {
        id: blurred
        anchors.fill: parent
        visible: backdrop.effectsAvailable && backdrop.factor > 0
        opacity: backdrop.factor
        scale: backdrop.zoom

        // The blur runs at the copy's size (1/8) into a cached layer, which changes only when
        // the copy is taken again, and is drawn scaled up with smooth filtering: a blurred
        // picture has no detail that the small texture loses.
        Item {
            id: smallBlur
            width: Math.max(1, Math.ceil(backdrop.width * backdrop.copyScale))
            height: Math.max(1, Math.ceil(backdrop.height * backdrop.copyScale))
            transform: Scale {
                xScale: backdrop.width / smallBlur.width
                yScale: backdrop.height / smallBlur.height
            }
            layer.enabled: backdrop.effectsAvailable
            layer.smooth: true

            MultiEffect {
                anchors.fill: parent
                source: copy
                blurEnabled: true
                blur: 1.0
                blurMax: Math.max(2, Math.min(64, Math.round(backdrop.blurPx)))
                autoPaddingEnabled: false
            }
        }
    }

    Motion {
        id: motion
    }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: Qt.rgba(PfStyle.dimIdle.r + (PfStyle.dimActive.r - PfStyle.dimIdle.r) * backdrop.factor,
                       PfStyle.dimIdle.g + (PfStyle.dimActive.g - PfStyle.dimIdle.g) * backdrop.factor,
                       PfStyle.dimIdle.b + (PfStyle.dimActive.b - PfStyle.dimIdle.b) * backdrop.factor,
                       backdrop.idleDim + (backdrop.promptDim - backdrop.idleDim) * backdrop.factor)

        // A brightness reading (a new wallpaper) changes the dim smoothly while nothing else moves.
        Behavior on color {
            enabled: motion.animate && (backdrop.factor === 0 || backdrop.factor === 1)
            ColorAnimation { duration: motion.surface }
        }
    }
}
