/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasma Fusion metrics: the user's text scale and the device-pixel grid of one window.
    The source is packages/common/FusionMetrics.qml; tools/build.d copies it into every package
    that shows text (do not edit the copies). Create one per window (an applet's root, each
    pop-up or Dialog mainItem, the window switcher, the lock screen) and pass it down:

      FusionMetrics { id: m; area: <availableScreenRect | clientArea(MaximizeArea) | window rect> }
      font.pixelSize: m.font(13)          text of the board's 13 px
      height: m.px(26)                    a control that holds text, snapped to device pixels
      width: m.windowSize(m.px(356))      a size that becomes a window size

    Three classes of values (docs/parts/*.md "Text scale"): design constants (radii, 1 px
    edges, focus rings, shadows, dots, glyph strokes) are never scaled; text and everything
    that holds text goes through font() and px(); screen-driven values come from `area`.
    Only bindings: nothing here runs on a timer or per frame.
*/
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: m

    visible: false
    width: 0
    height: 0

    // The screen area this window lays itself out in (logical px).
    property rect area: Qt.rect(0, 0, 1440, 900)

    // Device pixels per logical pixel of this window's screen; two monitors can differ. A
    // component that sizes a window before the window exists (KWin's switcher) sets
    // `screenScale` from its output instead.
    property real screenScale: 0
    readonly property real dpr: screenScale > 0 ? screenScale : Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1

    // Text scale: the user's UI font against the design font (Manrope 9.75 pt = 13 px), so it
    // is exactly 1 at the Plasma Fusion default and the boards stay exact. The point size is
    // continuous; the grid unit (fallback for a font set in pixels) moves in steps of 2 px.
    readonly property real ts: {
        const pt = Kirigami.Theme.defaultFont.pointSize;
        const s = pt > 0 ? pt / 9.75 : Kirigami.Units.gridUnit / 18;
        return Math.max(0.85, Math.min(1.6, s));
    }

    // Font families, resolved once per window (not in every text item; Qt.fontFamilies() builds
    // the whole list): Manrope for UI text, Space Grotesk for display figures. Missing families
    // fall back to the Plasma UI font.
    readonly property var families: {
        const installed = Qt.fontFamilies();
        const ui = installed.indexOf("Manrope") !== -1 ? "Manrope" : Kirigami.Theme.defaultFont.family;
        return {
            ui: ui,
            display: installed.indexOf("Space Grotesk") !== -1 ? "Space Grotesk" : ui
        };
    }
    readonly property string family: families.ui
    readonly property string displayFamily: families.display

    // Board px of text -> pixel size (fractional; Qt rounds it to whole pixels).
    function font(v: real): real {
        return v * ts;
    }
    // Whole device pixels.
    function snap(v: real): real {
        return Math.round(v * dpr) / dpr;
    }
    // Text-driven sizes: control heights, padding next to text, widths that hold text.
    function px(v: real): real {
        return snap(v * ts);
    }
    // "1 px" design edges: 1 device px up to 1.5, 2 device px from 1.75.
    readonly property real hairline: Math.max(1, Math.floor(dpr + 0.25)) / dpr

    // Modes and breakpoints (logical px of `area`).
    readonly property bool touch: Kirigami.Settings.tabletMode || Kirigami.Settings.hasTransientTouchInput
    readonly property bool portrait: area.height > area.width
    readonly property bool compactWidth: area.width < 1280 * Math.min(ts, 1.25)
    readonly property bool compactHeight: area.height < 800
    readonly property bool wide: area.width >= 2200

    // Hit targets: in touch mode at least 44 px (48 px for a target on a screen edge), with
    // the drawn size unchanged; otherwise `v`.
    function hit(v, edge) {
        return touch ? Math.max(v, px(edge ? 48 : 44)) : v;
    }

    // Smallest logical step that is a whole number of device px (3 at 4/3, 4 at 5/4, 2 at 3/2;
    // 1 when there is none, as at 1.325). For sizes that become window sizes.
    readonly property int step: {
        for (let n = 1; n <= 12; ++n) {
            if (Math.abs(n * dpr - Math.round(n * dpr)) < 0.01) {
                return n;
            }
        }
        return 1;
    }
    function windowSize(v: real): int {
        return Math.round(v / step) * step;
    }
}
