/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The "Tinted" glass material (EFFECTS.md 3.1, TABLET.md 4.1): a static blurred copy of the
    wallpaper plus a tint, for full-screen and large surfaces that must never be live-blurred
    (the tablet launcher sheet, the snap fill picker, the lock screen). The wallpaper is loaded at
    1/8 of the area's size, blurred once by one MultiEffect inside a small layer (about 181 x 113
    logical px for 1440 x 900) and shown scaled up; per frame this is one textured quad and one
    tint rectangle. The layer is rebuilt only when the picture, the colour variant or the size
    changes. Never animate this item's size; animate its opacity or a transform.

    Sources, in this order:
      sourceItem       an item captured once (ShaderEffectSource, live: false): the lock
                       screen's wallpaper item, KWin's DesktopBackground. Call recapture() when
                       the picture changes (and once after a thumbnail has rendered its first
                       frame; EFFECTS.md 6.4).
      followWallpaper  ask plasmashell for the wallpaper of `screenNumber`
                       (org.kde.PlasmaShell.wallpaper, image plugin key "Image"), again each time
                       the backdrop is shown and on plasmashell's wallpaperChanged signal. Only
                       inside plasmashell. The signal comes only from PlasmaShell.setWallpaper
                       (System Settings > Wallpaper); a change made by a desktop script
                       (plasma-apply-wallpaperimage) is picked up the next time it is shown.
      source           an image file, or a wallpaper package folder: for a package it takes
                       contents/images_dark/ in the dark variant when present, else
                       contents/images/, and the file whose size is closest to the area.
    With nothing loadable, with glass "solid" (Glass = Solid, the critical power tier), it draws
    only the tint at 0.94 opacity.

      FusionBackdrop { anchors.fill: parent; followWallpaper: true; screenNumber: Plasmoid.containment.screen; dark: palette.dark; glass: Plasmoid.configuration.glass }

    The source is packages/common/FusionBackdrop.qml; tools/build-lib/shared-qml.sh copies it
    into every package that uses it (do not edit the copies).
*/
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import org.kde.plasma.workspace.dbus as DBus

Item {
    id: backdrop

    property url source
    property Item sourceItem: null
    property bool followWallpaper: false
    property int screenNumber: 0
    property bool dark: true
    // Glass level: "full" and "reduced" draw the tinted picture, "solid" only the tint.
    property string glass: "full"
    // Blur radius of the 1/8-size copy (calibrate against a live-blurred surface, EFFECTS X5).
    property int blurMax: 32

    // The tint (EFFECTS.md 3.1): dark rgba(12,15,28,.55), light rgba(236,240,248,.60); 0.94 when
    // solid or when there is no picture.
    readonly property bool solid: glass === "solid" || !ready
    readonly property color tint: dark
        ? Qt.rgba(12 / 255, 15 / 255, 28 / 255, solid ? 0.94 : 0.55)
        : Qt.rgba(236 / 255, 240 / 255, 248 / 255, solid ? 0.94 : 0.60)
    // A picture is loaded and blurred. Until then (and without one) the tint is drawn at 0.94.
    readonly property bool ready: sourceItem ? captured : picture.status === Image.Ready
    // The file in use (after the wallpaper and package lookup), for tests and logs.
    readonly property url file: resolvedFile

    // Take the sourceItem picture again.
    function recapture(): void {
        if (sourceItem) {
            capture.scheduleUpdate();
            captured = true;
        }
    }

    property bool captured: false
    property url wallpaperUrl
    property url resolvedFile
    readonly property url wanted: followWallpaper ? wallpaperUrl : source
    readonly property int smallWidth: Math.max(1, Math.ceil(width / 8))
    readonly property int smallHeight: Math.max(1, Math.ceil(height / 8))

    function toUrl(value): string {
        const s = String(value || "");
        return s.startsWith("/") ? "file://" + s : s;
    }
    function isImageFile(u): bool {
        return /\.(png|jpe?g|webp|avif|jxl|bmp|svgz?)$/i.test(String(u));
    }

    // --- plasmashell's wallpaper (F17) ---
    function readWallpaper(): void {
        if (!followWallpaper) {
            return;
        }
        DBus.SessionBus.asyncCall({
            "service": "org.kde.plasmashell",
            "path": "/PlasmaShell",
            "iface": "org.kde.PlasmaShell",
            "member": "wallpaper",
            "arguments": [new DBus.uint32(Math.max(0, backdrop.screenNumber))],
            "signature": "(u)"
        }, reply => {
            const params = reply.value || {};
            backdrop.wallpaperUrl = params.Image ? backdrop.toUrl(params.Image) : "";
        }, () => {
            backdrop.wallpaperUrl = "";
        });
    }
    onFollowWallpaperChanged: readWallpaper()
    onScreenNumberChanged: readWallpaper()
    onVisibleChanged: if (visible) readWallpaper()
    DBus.SignalWatcher {
        enabled: backdrop.followWallpaper
        busType: DBus.BusType.Session
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        iface: "org.kde.PlasmaShell"
        // The D-Bus module hands numbers over as typed values (UINT32 with a `value`), not as
        // JavaScript numbers; compare them through their text.
        function dbuswallpaperChanged(screenNum) {
            if (Number(String(screenNum)) === backdrop.screenNumber) {
                backdrop.readWallpaper();
            }
        }
        // The other PlasmaShell signals are not needed; empty handlers keep the watcher quiet.
        function dbusshellChanged(shell) {
        }
        function dbuscolorChanged(color) {
        }
    }

    // --- image file or wallpaper package ---
    onWantedChanged: resolve()
    onDarkChanged: resolve()
    // A new size may prefer another file of a package (portrait, another aspect ratio).
    onSmallWidthChanged: if (!isImageFile(wanted)) resolve()
    onSmallHeightChanged: if (!isImageFile(wanted)) resolve()
    function resolve(): void {
        if (sourceItem) {
            return;
        }
        const w = String(wanted);
        if (w === "") {
            resolvedFile = "";
            lookup.active = false;
        } else if (isImageFile(w)) {
            resolvedFile = w;
            lookup.active = false;
        } else {
            // A package folder: list its images once, then drop the model (a folder model keeps a
            // file-system watcher, one inotify instance, for as long as it exists).
            lookup.active = false;
            lookup.active = true;
        }
    }
    // The listed image whose size (from a "WIDTHxHEIGHT" file name) is closest to the area in
    // device pixels, aspect ratio first. Only files inside `folder` count: a folder model given a
    // folder that does not exist lists the parent folder instead (Qt 6.11, measured).
    function pickClosest(model, folder: string): string {
        const w = backdrop.Window.window;
        const dpr = w && w.devicePixelRatio > 0 ? w.devicePixelRatio : Math.max(1, Screen.devicePixelRatio);
        const W = backdrop.width * dpr;
        const H = backdrop.height * dpr;
        let best = "";
        let bestScore = Infinity;
        for (let i = 0; i < model.count; ++i) {
            const url = String(model.get(i, "fileUrl"));
            if (!url.startsWith(folder)) {
                continue;
            }
            const m = /(\d+)x(\d+)/.exec(String(model.get(i, "fileName")));
            const score = m && W > 0 && H > 0
                ? 4 * Math.abs(Math.log((m[1] / m[2]) / (W / H))) + Math.abs(Math.log((m[1] * m[2]) / (W * H)))
                : 1e6 + i;
            if (score < bestScore) {
                bestScore = score;
                best = url;
            }
        }
        return best;
    }
    Loader {
        id: lookup
        active: false
        // One folder model, first on images_dark/ (dark variant only), then on images/.
        sourceComponent: FolderListModel {
            id: finder
            readonly property string base: String(backdrop.wanted).replace(/\/+$/, "") + "/contents/"
            folder: finder.base + (backdrop.dark ? "images_dark/" : "images/")
            nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.avif", "*.jxl", "*.svg", "*.svgz"]
            showDirs: false
            onStatusChanged: {
                if (status !== FolderListModel.Ready) {
                    return;
                }
                const here = String(folder);
                const file = backdrop.pickClosest(finder, here);
                if (file === "" && here.endsWith("/images_dark/")) {
                    folder = finder.base + "images/";
                    return;
                }
                Qt.callLater(() => {
                    backdrop.resolvedFile = file;
                    lookup.active = false;
                });
            }
        }
    }

    // --- the blurred copy: small, layered, shown scaled up ---
    Item {
        id: small
        visible: !backdrop.solid
        width: backdrop.smallWidth
        height: backdrop.smallHeight
        transform: Scale {
            xScale: backdrop.width / small.width
            yScale: backdrop.height / small.height
        }
        layer.enabled: visible
        layer.smooth: true

        Image {
            id: picture
            anchors.fill: parent
            visible: false
            // Nothing is loaded while only the tint is drawn (Glass = Solid).
            source: backdrop.sourceItem || backdrop.glass === "solid" ? "" : backdrop.resolvedFile
            sourceSize.width: small.width
            sourceSize.height: small.height
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }
        ShaderEffectSource {
            id: capture
            anchors.fill: parent
            visible: false
            sourceItem: backdrop.sourceItem
            live: false
            hideSource: false
            textureSize: Qt.size(small.width, small.height)
        }
        MultiEffect {
            anchors.fill: parent
            source: backdrop.sourceItem ? capture : picture
            blurEnabled: true
            blur: 1.0
            blurMax: backdrop.blurMax
            autoPaddingEnabled: false
        }
    }

    Rectangle {
        anchors.fill: parent
        color: backdrop.tint
    }

    onSourceItemChanged: {
        captured = false;
        if (sourceItem) {
            recapture();
        }
    }
    Component.onCompleted: {
        readWallpaper();
        resolve();
        if (sourceItem) {
            recapture();
        }
    }
}
