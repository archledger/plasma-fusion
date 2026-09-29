/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Shapes

import "../code/launcher.js" as Launcher

// A stroked line icon drawn from the design's 24x24 path data.
Item {
    id: glyph

    property string name: ""
    property color color: "white"
    property real size: 18
    property real strokeWidth: 1.8

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: glyph.name.length > 0

        ShapePath {
            strokeColor: glyph.color
            strokeWidth: glyph.strokeWidth * glyph.size / 24
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            scale: Qt.size(glyph.size / 24, glyph.size / 24)

            PathSvg {
                path: Launcher.glyphs[glyph.name] || ""
            }
        }
    }
}
