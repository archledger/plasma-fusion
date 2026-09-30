// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Fixture for tools/checks/motion-lint.sh: "expect: RULE" marks each line the lint must report;
// every other line must stay silent. Not a working component.
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root
    property bool cond: false
    Motion { id: motion }
    Behavior on x { NumberAnimation {} } // expect: no-duration
    Behavior on y { NumberAnimation { duration: motion.hover; easing.type: motion.standardEasing } }
    NumberAnimation { duration: 150 } // expect: literal-duration
    NumberAnimation { duration: 2 * 500 } // expect: literal-duration
    NumberAnimation { duration: motion.surface * 1.2 }
    NumberAnimation { duration: 2 * motion.pulse }
    NumberAnimation { duration: root.cond ? 600 : 0 } // expect: literal-duration
    NumberAnimation { duration: Kirigami.Units.veryLongDuration * 2 } // expect: over-max
    NumberAnimation { duration: Kirigami.Units.longDuration }
    NumberAnimation { duration: Kirigami.Units.longDuration * 2 }
    SequentialAnimation { loops: Animation.Infinite // expect: infinite-loop
        PauseAnimation { duration: motion.toggle }
    }
    SequentialAnimation { loops: motion.loops(3); PauseAnimation { duration: motion.pulse } }
    OpacityAnimator { target: root } // expect: no-duration
    SpringAnimation { spring: 2 } // expect: no-duration
    // NumberAnimation { duration: 100 } in a comment is not code
    /* ColorAnimation { duration: 90 }
       NumberAnimation {} */
    function restart(anim) {
        anim.duration = 300; // expect: literal-duration
        anim.duration = motion.popupOut;
    }
    function make(): NumberAnimation { return null; }
    Timer { interval: 500 }
    property string label: "duration: 100"
    FrameAnimation { running: false }
    ParallelAnimation { NumberAnimation { duration: motion.popupIn; easing.type: Easing.Bezier; easing.bezierCurve: motion.decelerate } }
}
