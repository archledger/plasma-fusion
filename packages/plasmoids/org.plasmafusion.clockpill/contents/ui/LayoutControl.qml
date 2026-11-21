/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import org.kde.plasma.core as PlasmaCore

// The workspace layout control of the top bar pill, read only: the dynamic tiler's mode for this
// bar's view, as the bar's layout state has it (LayoutState.qml, `mode`). It shows only a mode an
// answer confirmed, tiled or floating. Unknown - no answer taken yet, or the bar asking again - and
// unavailable - the provider cannot tile, or KWin has no such output - show nothing, so nothing
// that looks as if it worked appears without the placement script's word. The Floating and Tiled
// choices come later (tasks/workspace-layout-control/todo.md, P6); until then it takes no focus
// and no click, and a wheel turned over it reaches the pill.
//
// No board draws it; every value is a board's (docs/parts/shell-topbar.md, "Workspace layout
// control"): a 14 px line glyph (the LiveChips board's glyph size, stroked 1.8 as the shell boards'
// line icons), 6 px to its label (a LiveChips chip's own gap after its glyph) and the label in
// Manrope 13 px 600 (the pill's text size, the weight of the TabletSnap board's window-card rows),
// in the pill's text colour. The glyphs are the Icons board's Snap symbol without its last stroke:
// tiled, the window frame and its divider; floating, the frame alone.
Item {
    id: control

    // The layout state's mode: unknown, unavailable, floating or tiled.
    required property string mode
    // The window's metrics (one per window, passed down from its root).
    required property FusionMetrics metrics
    // The pill's text colour.
    required property color color
    // The width budget's step for the control: 0 the glyph and its label, 1 the glyph alone (its
    // accessible name still says the mode), 2 nothing.
    property int level: 0
    property int location: PlasmaCore.Types.TopEdge
    // Height of the hit area: the pill's height.
    property real cellHeight: 24
    // The label's size in board px: the pill's text size.
    property real px: 13

    readonly property bool available: mode === "tiled" || mode === "floating"
    readonly property bool tiled: mode === "tiled"
    readonly property real glyphSize: metrics.px(14)
    readonly property real gap: metrics.px(6)
    // The label's box is as wide as the wider of the two labels, so a change of mode never
    // changes the pill's width (as the time's box, BACKLOG M8).
    readonly property real labelWidth: Math.ceil(Math.max(tiledMetrics.advanceWidth, floatingMetrics.advanceWidth))
    // The widths at levels 0 and 1, whatever the mode and level: the width budget's measures.
    readonly property real fullWidth: glyphSize + gap + labelWidth
    readonly property real compactWidth: glyphSize

    readonly property string tiledText: i18nc("@info layout control, the windows of this workspace are tiled", "Tiled")
    readonly property string floatingText: i18nc("@info layout control, the windows of this workspace are not tiled",
                                                  "Floating")

    implicitWidth: !available || level >= 2 ? 0 : level === 1 ? compactWidth : fullWidth
    implicitHeight: cellHeight
    visible: available && level < 2

    Accessible.role: Accessible.StaticText
    Accessible.name: tiled ? i18nc("@info accessible name of the layout control", "Dynamic tiling: Tiled")
                           : i18nc("@info accessible name of the layout control", "Dynamic tiling: Floating")
    Accessible.description: tip.subText

    TextMetrics {
        id: tiledMetrics
        font: label.font
        text: control.tiledText
    }
    TextMetrics {
        id: floatingMetrics
        font: label.font
        text: control.floatingText
    }

    PlasmaCore.ToolTipArea {
        id: tip
        objectName: "layoutTip"
        anchors.fill: parent
        location: control.location
        mainText: control.tiled ? control.tiledText : control.floatingText
        subText: control.tiled ? i18nc("@info:tooltip layout control", "The dynamic tiler arranges this workspace's windows")
                               : i18nc("@info:tooltip layout control", "The dynamic tiler does not arrange this workspace")
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: control.gap

        // A line glyph of the boards: an SVG path on a 24 x 24 grid, stroked 1.8 (the pen
        // widget's LineIcon).
        Item {
            id: glyph
            objectName: "layoutGlyph"

            readonly property string path: control.tiled ? "M4 5h16v14H4zM12 5v14" : "M4 5h16v14H4z"
            readonly property color color: control.color

            anchors.verticalCenter: parent.verticalCenter
            width: control.glyphSize
            height: control.glyphSize

            Shape {
                width: 24
                height: 24
                scale: control.glyphSize / 24
                transformOrigin: Item.TopLeft
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: glyph.color
                    strokeWidth: 1.8
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: glyph.path }
                }
            }
        }

        FusionText {
            id: label
            objectName: "layoutLabel"
            anchors.verticalCenter: parent.verticalCenter
            visible: control.level === 0
            width: control.labelWidth
            // Set, so that a mirrored layout mirrors it and the label keeps to its glyph's side of
            // the box: an alignment left unset follows the text's own direction.
            horizontalAlignment: Text.AlignLeft
            metrics: control.metrics
            px: control.px
            weight: 600
            color: control.color
            text: control.tiled ? control.tiledText : control.floatingText
        }
    }
}
