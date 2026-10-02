/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    An app icon as the dock and the launcher show it (ADAPTIVE.md 5.4 and fix 27): an icon that
    the Plasma Fusion icon theme draws as a Fusion tile is shown as it is; any other app's icon
    (a Breeze or third-party icon) is drawn on a neutral Fusion tile, so the row stays a row of
    tiles. An app whose desktop id (`iconName`) has a designed tile shows that tile, whatever icon
    its desktop entry names (KDebugSettings names debug-run, which the theme keeps for the action).
    With familiar app icons on (packages/appicons) an app without a design shows its familiar tile
    (its own icon drawn on a Fusion tile, looked up by desktop id), and only an app without one gets
    the neutral tile. A drop-in for Kirigami.Icon in DOCK-2 and LAUNCH-1:

      FusionIconTile {
          size: 48                    // the tile's size; the icon inside follows
          source: model.decoration    // what Kirigami.Icon takes: a name, a URL or a QIcon
          iconName: model.iconName    // needed when `source` is not a name (a QIcon)
      }

    `foreign` says whether the neutral tile is drawn; the default decides it from the icon name
    against the Fusion icon theme's app names (FusionIconNames.js, generated at build time from
    generators/icons/names.py, with the icon loader's dash fallback: "google-chrome-canary"
    finds the "google-chrome" tile). Bind `foreign: false` while another icon theme is active.
    No shadow here: the dock and the launcher put their shared shadow under the tile
    (FusionShadow, radius 0.234 x size). Plain rectangles, no layer, no effect.

    Tile anatomy (AppIcon board, 64-unit tile, art_tiles.py): radius 15, a 4-unit lip under a
    60-unit base, a 9 % white sheen on the top 28 units, a 1-unit 14 % white edge. The neutral
    tile is the light board neutral in both variants (like the Calendar tile), so full-colour
    icons keep their contrast. The source is packages/common/FusionIconTile.qml;
    tools/build-lib/shared-qml.sh copies it and FusionIconNames.js into every package that
    uses it (do not edit the copies).
*/
import QtQuick
import org.kde.kirigami as Kirigami
import "FusionIconNames.js" as FusionIconNames

Item {
    id: tile

    // What Kirigami.Icon shows: an icon name, a URL or a QIcon.
    property var source
    // The icon's theme name, for the coverage check; taken from `source` when it is a name.
    property string iconName: typeof source === "string" ? source : ""
    // Draw the neutral tile behind the icon (true for icons without a Fusion tile).
    property bool foreign: iconName !== "" && !FusionIconNames.covers(iconName) && !familiar
    // The app's designed tile, by desktop id: shown when the name resolves (the Fusion icon theme
    // is active).
    readonly property bool designed: iconName !== "" && FusionIconNames.designed(iconName)
    readonly property bool ownTile: designed && ownProbe.status === Kirigami.Icon.Ready
    // The app's familiar tile (packages/appicons writes one per app without a design, under this
    // name: no dash, so the icon loader's dash fallback cannot answer it with another icon).
    readonly property string familiarName: "plasmafusion_app." + iconName.replace(/-/g, "_")
    readonly property bool familiar: familiarProbe.status === Kirigami.Icon.Ready
    // Tile size in logical px (the dock's 48, the launcher's 60/72).
    property real size: 48
    // Size of a foreign icon inside the tile: 42 of 64 units, centred on the 60-unit base.
    property real glyphRatio: 42 / 64

    readonly property alias iconItem: glyph
    readonly property real unit: size / 64

    implicitWidth: size
    implicitHeight: size

    // Whole device pixels for the drawn glyph (the tile itself scales with the dock). The
    // window's ratio, not Screen's (a whole number on Wayland at fractional scales).
    readonly property real dpr: {
        const w = Window.window;
        const r = w && w.devicePixelRatio > 0 ? w.devicePixelRatio : Screen.devicePixelRatio;
        return r > 0 ? r : 1;
    }
    function snap(v: real): real {
        return Math.round(v * dpr) / dpr;
    }

    // Lip (whole tile, darker), base (top 60 units), sheen, edge.
    Rectangle {
        anchors.fill: parent
        visible: tile.foreign
        radius: 15 * tile.unit
        color: "#d5d9e3"
    }
    Rectangle {
        visible: tile.foreign
        width: parent.width
        height: 60 * tile.unit
        radius: 15 * tile.unit
        color: "#f4f5f9"
    }
    Rectangle {
        visible: tile.foreign
        width: parent.width
        height: 28 * tile.unit
        topLeftRadius: 15 * tile.unit
        topRightRadius: 15 * tile.unit
        color: Qt.rgba(1, 1, 1, 0.09)
    }
    // The board strokes a 14.5-radius outline centred 0.5 units inside the edge; a Rectangle
    // border lies inside its bounds, so the full-size rectangle with radius 15 covers the same
    // band.
    Rectangle {
        visible: tile.foreign
        anchors.fill: parent
        radius: 15 * tile.unit
        color: "transparent"
        border.width: tile.unit
        border.color: Qt.rgba(1, 1, 1, 0.14)
    }

    // Look the app's own tiles up (see `ownTile` and `familiar`); draw nothing.
    Kirigami.Icon {
        id: ownProbe
        visible: false
        width: 1
        height: 1
        fallback: ""
        source: tile.designed ? tile.iconName : ""
    }
    Kirigami.Icon {
        id: familiarProbe
        visible: false
        width: 1
        height: 1
        fallback: ""
        source: tile.iconName !== "" && !tile.designed ? tile.familiarName : ""
    }

    Kirigami.Icon {
        id: glyph
        readonly property real glyphSize: tile.foreign ? tile.snap(tile.size * tile.glyphRatio) : tile.size
        width: glyphSize
        height: glyphSize
        x: tile.snap((tile.width - width) / 2)
        y: tile.snap(((tile.foreign ? 60 * tile.unit : tile.height) - height) / 2)
        source: tile.ownTile ? tile.iconName : tile.familiar ? tile.familiarName : tile.source
        // Accessibility belongs to the button that holds the tile.
        Accessible.ignored: true
    }
}
