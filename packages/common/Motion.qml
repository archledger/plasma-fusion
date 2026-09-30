/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasma Fusion motion tokens (EFFECTS.md 6.1). Every Fusion animation takes its duration and
    easing from here, never from a number, so Plasma's animation speed (System Settings >
    Animation speed, kdeglobals [KDE] AnimationDurationFactor) and reduced motion ("Instant",
    factor 0) reach all of them. The source is packages/common/Motion.qml; tools/build-lib/
    shared-qml.sh copies it into every package that uses it (do not edit the copies).

      Motion { id: motion }
      Behavior on color { enabled: motion.animate; ColorAnimation { duration: motion.hover } }
      NumberAnimation { duration: motion.popupIn; easing.type: Easing.Bezier; easing.bezierCurve: motion.decelerate }
      NumberAnimation { duration: motion.popupOut; easing.type: motion.exitEasing }
      SequentialAnimation { loops: motion.loops(3); ... duration: motion.pulse ... }

    Tokens at factor 1 (they scale with the factor; all are 0 when `reduced`):
      press 0, pressScale 80, hover 100, toggle 150, popupIn 200, popupOut 150, surface 250,
      pulse 500 (one half of a pulse cycle), max 400 (upper bound for anything user-triggered).
    Rules: animate opacity, scale, x/y and colours only; no loop longer than 3 cycles; when
    `reduced`, loops do not start and slides become an instant change (`animate` is false).
    Qt animators (OpacityAnimator, ...) do not fire reliably at duration 0 (libplasma units.cpp,
    QTBUG-39766): gate them with `enabled: motion.animate` or use NumberAnimation.
    Only bindings: nothing here runs on a timer or per frame.
*/
import QtQuick
import org.kde.kirigami as Kirigami

QtObject {
    id: motion

    // Kirigami's long duration: round(200 ms x factor), at least 1 ms, so exactly 1 at factor 0
    // (libplasma KirigamiPlasmaStyle units.cpp; short = long / 2 and veryLong = long * 2 with
    // integer division). It follows a factor change written with --notify at once.
    readonly property int unit: Kirigami.Units.longDuration
    readonly property bool reduced: unit <= 1
    readonly property bool animate: !reduced

    // Durations (ms).
    readonly property int press: 0
    readonly property int pressScale: reduced ? 0 : Math.round(Kirigami.Units.shortDuration * 0.8)
    readonly property int hover: reduced ? 0 : Kirigami.Units.shortDuration
    readonly property int toggle: reduced ? 0 : Math.round(Kirigami.Units.shortDuration * 1.5)
    readonly property int popupIn: reduced ? 0 : Kirigami.Units.longDuration
    readonly property int popupOut: reduced ? 0 : Math.round(Kirigami.Units.longDuration * 0.75)
    readonly property int surface: reduced ? 0 : Math.round(Kirigami.Units.longDuration * 1.25)
    readonly property int pulse: reduced ? 0 : Math.round(Kirigami.Units.longDuration * 2.5)
    readonly property int max: reduced ? 0 : Kirigami.Units.veryLongDuration

    // Easing. popupIn uses `decelerate` (easing.type: Easing.Bezier); closing uses exitEasing;
    // hover, toggle, press and surface use standardEasing. No bounce or overshoot.
    readonly property int standardEasing: Easing.OutCubic
    readonly property int exitEasing: Easing.InCubic
    readonly property var decelerate: [0, 0, 0, 1, 1, 1]

    // A token times a ratio (for example the lock prompt: scaled(surface, 1.2) = 300 ms), never
    // longer than `max`.
    function scaled(token: int, ratio: real): int {
        return Math.min(max, Math.round(token * ratio));
    }

    // Loop count for a repeating animation: at most 3 cycles, 0 (the animation does not run)
    // when reduced.
    readonly property int maxLoops: 3
    function loops(n: int): int {
        return reduced ? 0 : Math.max(0, Math.min(n, maxLoops));
    }
}
