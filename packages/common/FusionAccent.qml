/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasma Fusion accent colour (decision 3: every Fusion surface follows the user's accent).
    Colours come from the colour scheme through Kirigami.Theme, never from a literal:

      accent      the accent for rings, markers, zones, slider fills and selected outlines:
                  DecorationHover in a dark scheme (#5b9dff in Plasma Fusion Dark) and
                  DecorationFocus in a light one (#2f6fdf in Plasma Fusion Light)
      accentText  text or glyph colour drawn on an `accent` fill (white or the board's ink,
                  whichever reaches 4.5:1; #141827 on #5b9dff, white on #2f6fdf)
      fill        the selection fill (Selection BackgroundNormal, #2f6fdf in both schemes)
      fillText    text on `fill` (Selection ForegroundNormal, white)
      hoverAccent DecorationHover in both variants (#5b9dff)
      focusRing   DecorationFocus: the keyboard focus ring (#8ab8ff dark, #2f6fdf light)
      soft(a)     `accent` at alpha a (tints, zones, badges)

    When the user picks an accent (System Settings > Colours, or the Plasma Fusion page),
    Plasma writes it into DecorationFocus and DecorationHover (and a matching Selection fill,
    plasma-workspace kcms/colors/colorsapplicator.cpp), so all of these follow at once. The
    source is packages/common/FusionAccent.qml; tools/build-lib/shared-qml.sh copies it into
    every package that uses it (do not edit the copies). Create one per window, inside the
    item whose colour set it should follow (its parent, or `colorSource`), and pass it down:

      FusionAccent { id: tint }            // or: FusionAccent { id: tint; dark: palette.dark }
      color: tint.accent
      color: tint.soft(0.28)

    The colours are those of the parent's Kirigami colour set (`colorSource`): an invisible item's
    own Kirigami.Theme is never filled in when it is the first one in its branch (libplasma
    kirigamiplasmastyle/plasmatheme.cpp and qqc2-desktop-style plasmadesktoptheme.cpp skip items
    that are not visible; measured offscreen: all black). An invisible Item, so that it takes no
    room in a Row or a Layout. Only bindings: nothing here runs on a timer or per frame.
*/
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: tint

    visible: false
    width: 0
    height: 0

    // The visible item whose Kirigami colour set this follows.
    property Item colorSource: parent

    // Dark or light variant; a widget with its own "Colours: Dark/Light" option binds its value.
    property bool dark: Kirigami.ColorUtils.brightnessForColor(background) === Kirigami.ColorUtils.Dark

    readonly property color accent: dark ? hoverAccent : focusRing
    readonly property color accentText: readableOn(accent)
    readonly property color fill: colorSource ? colorSource.Kirigami.Theme.highlightColor : Kirigami.Theme.highlightColor
    readonly property color fillText: colorSource ? colorSource.Kirigami.Theme.highlightedTextColor : Kirigami.Theme.highlightedTextColor
    readonly property color hoverAccent: colorSource ? colorSource.Kirigami.Theme.hoverColor : Kirigami.Theme.hoverColor
    readonly property color focusRing: colorSource ? colorSource.Kirigami.Theme.focusColor : Kirigami.Theme.focusColor
    readonly property color background: colorSource ? colorSource.Kirigami.Theme.backgroundColor : Kirigami.Theme.backgroundColor

    // True while the colour scheme's own Plasma Fusion blue is in effect (no user accent), for
    // the few places that keep a board-exact shade only for the Fusion blue.
    readonly property bool schemeAccent: Qt.colorEqual(hoverAccent, "#5b9dff")
        && Qt.colorEqual(focusRing, dark ? "#8ab8ff" : "#2f6fdf")

    // The board's ink for text on light accents (Plasma Fusion Light text colour).
    readonly property color ink: "#141827"

    function soft(alpha: real): color {
        return Qt.rgba(accent.r, accent.g, accent.b, alpha);
    }

    // WCAG 2 relative luminance and contrast.
    function luminance(c: color): real {
        const lin = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    }
    function contrast(a: color, b: color): real {
        const la = luminance(a);
        const lb = luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }
    // White when it reaches 4.5:1 on `background`, otherwise the better of white and the ink.
    function readableOn(background: color): color {
        const white = Qt.rgba(1, 1, 1, 1);
        const onWhite = contrast(background, white);
        if (onWhite >= 4.5) {
            return white;
        }
        return contrast(background, ink) > onWhite ? ink : white;
    }
}
