/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Offscreen probe of the shared blocks (run by offscreen.sh, which stages this file next to
    the blocks). Arguments after "--": WALLPAPER_PACKAGE_URL OUTDIR LABEL. Prints one line
    "PROBE {json}" and saves LABEL-tiles.png and LABEL-backdrop.png into OUTDIR.
*/
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami

Window {
    id: win

    width: 480
    height: 360
    visible: true
    color: "#1b2031"

    readonly property var args: {
        const a = Qt.application.arguments;
        const i = a.indexOf("--");
        return i >= 0 ? a.slice(i + 1) : [];
    }
    readonly property string wallpaper: args[0] || ""
    readonly property string outDir: args[1] || "."
    readonly property string label: args[2] || "probe"

    Motion {
        id: motion
    }
    FusionTablet {
        id: tabletState
    }
    FusionMetrics {
        id: m
        tablet: tabletState.tablet
        area: Qt.rect(0, 0, win.width, win.height)
    }
    FusionAccent {
        id: tint
    }

    Row {
        id: tiles
        x: 12
        y: 12
        spacing: 10
        Repeater {
            id: tileRepeater
            model: ["firefox", "org.kde.kcalc", "org.example.NoSuchApp", "google-chrome-canary", "org.kde.konsole", "vlc", "/opt/example/icon.png", ""]
            FusionIconTile {
                required property string modelData
                size: 48
                source: modelData
            }
        }
    }

    FusionBackdrop {
        id: backdrop
        x: 12
        y: 80
        width: 360
        height: 225
        source: win.wallpaper
        dark: true
    }
    FusionBackdrop {
        id: solidBackdrop
        x: 380
        y: 80
        width: 80
        height: 50
        source: win.wallpaper
        dark: false
        glass: "solid"
    }

    property int saved: 0
    function finish(): void {
        const foreign = [];
        for (let i = 0; i < tileRepeater.count; ++i) {
            const t = tileRepeater.itemAt(i);
            foreign.push([t.iconName, t.foreign, t.iconItem.width]);
        }
        const out = {
            dpr: Screen.devicePixelRatio,
            factorUnit: motion.unit,
            reduced: motion.reduced,
            animate: motion.animate,
            tokens: {
                press: motion.press, pressScale: motion.pressScale, hover: motion.hover, toggle: motion.toggle,
                popupIn: motion.popupIn, popupOut: motion.popupOut, surface: motion.surface, pulse: motion.pulse,
                max: motion.max, lockPrompt: motion.scaled(motion.surface, 1.2), loops3: motion.loops(3), loops9: motion.loops(9)
            },
            tablet: tabletState.tablet,
            tabletAvailable: tabletState.available,
            tabletFromKWin: tabletState.fromKWin,
            metricsTouch: m.touch,
            metricsTablet: m.tablet,
            hairline: m.hairline,
            accent: String(tint.accent),
            accentText: String(tint.accentText),
            fill: String(tint.fill),
            fillText: String(tint.fillText),
            focusRing: String(tint.focusRing),
            soft: String(tint.soft(0.28)),
            schemeAccent: tint.schemeAccent,
            dark: tint.dark,
            tiles: foreign,
            backdropReady: backdrop.ready,
            backdropSolid: backdrop.solid,
            backdropFile: String(backdrop.file),
            backdropTint: String(backdrop.tint),
            solidTint: String(solidBackdrop.tint),
            solidReady: solidBackdrop.ready
        };
        console.warn("PROBE " + JSON.stringify(out));
        tiles.grabToImage(r => { r.saveToFile(win.outDir + "/" + win.label + "-tiles.png"); win.saved++; });
        backdrop.grabToImage(r => { r.saveToFile(win.outDir + "/" + win.label + "-backdrop.png"); win.saved++; });
    }
    onSavedChanged: if (saved === 2) Qt.quit()

    // Wait for the backdrop (folder listing and image load are asynchronous), at most 5 s.
    Timer {
        interval: 100
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            ++ticks;
            if ((backdrop.ready && ticks > 3) || ticks > 50) {
                running = false;
                win.finish();
            }
        }
    }
}
