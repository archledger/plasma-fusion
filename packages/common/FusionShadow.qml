// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick

/*
    FusionShadow: the soft drop shadow of a rounded box, one small shader (shaders/fusionshadow.frag).
    It replaces QtQuick.Effects' RectangularShadow, which in Qt 6.11.2 keeps about 6 KiB of memory
    for every instance that is destroyed (STRESS-1, 2026-10-01: 300 rounds of 200 shadows grew a
    plain Qt window from 168 to 335 MiB; Rectangle, ShaderEffect and MultiEffect stay flat). Tiles
    in the launcher, the tablet home screen and the dock are created and destroyed all the time
    (opening the launcher, scrolling, rotating), so plasmashell grew with every use.

    Same use as RectangularShadow: fill the shadowed item, then set what differs:

      FusionShadow {
          anchors.fill: icon
          offset.y: 3
          blur: 6
          radius: 0.234 * icon.size
          color: pal.iconShadow
      }

    offset moves the shadow, blur is the falloff width outside the box (px), spread grows the box
    on every side (px; negative shrinks it), radius is the box's corner radius.
*/
Item {
    id: shadow

    property point offset: Qt.point(0, 0)
    property real blur: 10
    property real spread: 0
    property real radius: 0
    property color color: "black"

    ShaderEffect {
        readonly property real grow: shadow.spread + shadow.blur
        x: shadow.offset.x - grow
        y: shadow.offset.y - grow
        width: Math.max(0, shadow.width + 2 * grow)
        height: Math.max(0, shadow.height + 2 * grow)
        visible: shadow.width > 0 && shadow.height > 0 && shadow.color.a > 0

        readonly property vector2d itemSize: Qt.vector2d(width, height)
        readonly property vector2d halfBox: Qt.vector2d(Math.max(0, shadow.width / 2 + shadow.spread),
                                                        Math.max(0, shadow.height / 2 + shadow.spread))
        readonly property real radius: Math.max(0, Math.min(shadow.radius + shadow.spread, halfBox.x, halfBox.y))
        readonly property real blur: Math.max(0, shadow.blur)
        readonly property color color: shadow.color
        fragmentShader: Qt.resolvedUrl("shaders/fusionshadow.frag.qsb")
    }
}
