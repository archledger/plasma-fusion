/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import org.kde.plasma.core as PlasmaCore

// The workspace layout control of the top bar pill: the dynamic tiler's mode for this bar's view,
// as the bar's layout state has it (LayoutState.qml, `mode`). It shows only a mode an answer
// confirmed, tiled or floating. Unknown - no answer taken yet, or the bar asking again - and
// unavailable - the provider cannot tile, or KWin has no such output - show nothing, so nothing
// that looks as if it worked appears without the placement script's word.
//
// It is read only unless its owner makes it `interactive`, which the owner does only while the
// layout actions are available: until then, and whenever a provider refuses them, it takes no
// focus and no click, and a wheel turned over it reaches the pill. Interactive, it asks its owner
// for the layout menu (LayoutMenu.qml) and presents the outcomes the owner hands it; it decides
// nothing itself (docs/parts/shell-topbar.md, "Workspace layout control").
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

    // A Tab stop that opens the layout menu. Its owner sets it while the layout actions are
    // available; false, the control is the read-only one.
    property bool interactive: false
    // The window's accent (FusionAccent, one per window, passed down): the focus ring and the
    // opener's look. Unset, neither shows.
    property FusionAccent accent: null
    // The layout menu is open, or closed a moment ago: a press then is the user's close, so that
    // the click after it does not open the menu again.
    property bool menuOpen: false
    // A choice is awaited with the menu closed.
    property bool pending: false

    // Asks the owner for the layout menu, saying how - pointer, keys or accessibility - so that
    // the menu can give its row a focus reason that shows the ring only for the keyboard.
    signal menuRequested(string by)
    // A press on the control while its menu is open: the user's close.
    signal menuDismissed()

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
    // How far the opener's look reaches past each side: half the pill's padding (the Main board's
    // padding 0 12; the control shows only outside tablet posture), as the focus ring reaches
    // outside the control, so that the pill keeps its width.
    readonly property real reach: metrics.px(12) / 2

    readonly property string tiledText: i18nc("@info layout control, the windows of this workspace are tiled", "Tiled")
    readonly property string floatingText: i18nc("@info layout control, the windows of this workspace are not tiled",
                                                  "Floating")
    readonly property string changedText: i18nc("@info:status layout control, the workspace changed under the choice",
                                                 "The workspace changed")
    readonly property string genericText: i18nc("@info:status layout control, a choice failed", "Couldn't change the layout")
    readonly property string noAppText: i18nc("@info:status layout control, Tiled found no app window", "No app window to tile")
    readonly property string waitingText: i18nc("@info:tooltip layout control, a choice was sent", "Waiting for an answer")
    // The keys that open the menu, as on the date.
    readonly property var openingKeys: [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select]

    implicitWidth: !available || level >= 2 ? 0 : level === 1 ? compactWidth : fullWidth
    implicitHeight: cellHeight
    visible: available && level < 2
    activeFocusOnTab: interactive && visible

    Accessible.role: interactive ? Accessible.ButtonDropDown : Accessible.StaticText
    Accessible.name: tiled ? i18nc("@info accessible name of the layout control", "Dynamic tiling: Tiled")
                           : i18nc("@info accessible name of the layout control", "Dynamic tiling: Floating")
    Accessible.description: tip.subText

    // The read-only control has no focus: one taken while it was interactive goes when the
    // layout actions go.
    onInteractiveChanged: {
        if (!interactive) {
            focus = false;
        }
    }

    // Return, Enter, Space and Select open the menu on a press, never on an auto-repeat: the
    // menu takes over the keys, and a held key repeats into it. The repeats are taken too, so that
    // they go no further. Arrows and Escape are left to the panel, which turns arrows into Tab and
    // Backtab and leaves the panel on Escape.
    Keys.onPressed: event => {
        if (!control.interactive || control.openingKeys.indexOf(event.key) === -1) {
            return;
        }
        if (!event.isAutoRepeat) {
            control.menuRequested("keys");
        }
        event.accepted = true;
    }

    // The accessible press action, connected only while interactive: a press action once
    // connected is offered to assistive technology, which the read-only control must not do.
    Connections {
        target: control.interactive ? control.Accessible : null
        function onPressAction(): void {
            control.menuRequested("accessibility");
        }
    }

    // The outcome texts (D10 of the P6 design), shared by the pill's notice and the menu's
    // status line, so that both say the same. `mode` is the mode the outcome concerns, empty for
    // a prepare with no choice queued, and `inMenu` words an unconfirmed outcome for the open
    // menu, where a new choice still prepares again, or for the pill.
    function outcomeText(reason: string, mode: string, inMenu: bool): string {
        const tiledChoice = mode === "tiled";
        switch (reason) {
        case "":
            return "";
        case "unconfirmed":
            return inMenu ? i18nc("@info:status layout menu, the provider has not answered yet", "No answer yet")
                          : i18nc("@info:status layout control, the provider did not answer", "Not confirmed");
        case "interrupted":
            return i18nc("@info:status layout control, the menu closed before the provider read the choice",
                         "Interrupted, try again");
        case "busy":
            return i18nc("@info:status layout control, another bar is changing a layout", "Busy, try again");
        case "cancelled":
            return i18nc("@info:status layout control, the tiling shortcut cancelled the choice", "Cancelled");
        case "stale-context":
        case "target-departed":
        case "view-changed":
        case "shell-replaced":
            return changedText;
        case "focus-changed":
            // A set refused so, or, with no choice or Tiled, a prepare that found no app to hand
            // off: the outcome carries no intent, and a prepare's is the one the menu shows.
            return mode === "floating" ? changedText : i18nc("@info:status layout menu, Tiled needs an app window to tile",
                                                             "Focus an app window first");
        case "no-target":
            // A prepare that found no app to tile, with no choice or Tiled queued, or a Tiled set.
            return mode === "floating" ? genericText : noAppText;
        case "not-eligible":
            return tiledChoice ? noAppText : genericText;
        case "tree-refused":
        case "admission-refused":
        case "unavailable":
            return tiledChoice ? i18nc("@info:status layout control, the dynamic tiler refused this workspace",
                                       "Couldn't tile this workspace")
                               : genericText;
        default:
            return genericText;
        }
    }

    // An outcome the owner presents: shown in the tooltip and the accessible description for 5 s
    // (quick settings' refused-state time), and cleared by an empty one, a done set's. The owner
    // announces it; the control never does, so that a reason is said once.
    function notify(reason: string, mode: string): void {
        d.notice = outcomeText(reason, mode, false);
        if (d.notice === "") {
            noticeTimer.stop();
        } else {
            noticeTimer.restart();
        }
    }

    QtObject {
        id: d
        property string notice: ""
    }
    Timer {
        id: noticeTimer
        objectName: "layoutNotice"
        interval: 5000
        onTriggered: d.notice = ""
    }

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

    // While its menu is open, the control alone takes the opener's look, which the pill takes
    // while the calendar is open: the accent at 35% with an inset 1 px edge (the QuickSettings
    // board's open status pill), a capsule of the pill's height.
    Rectangle {
        objectName: "layoutOpenLook"
        visible: control.interactive && control.menuOpen
        x: -control.reach
        width: control.width + 2 * control.reach
        height: control.cellHeight
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        antialiasing: true
        color: control.accent ? control.accent.soft(0.35) : "transparent"
        border.width: 1
        border.color: control.accent ? Qt.rgba(control.accent.focusRing.r, control.accent.focusRing.g, control.accent.focusRing.b, 0.5)
                                     : "transparent"
    }

    PlasmaCore.ToolTipArea {
        id: tip
        objectName: "layoutTip"
        anchors.fill: parent
        location: control.location
        // Not over its open menu, as the date's is not over the calendar.
        active: !(control.interactive && control.menuOpen)
        mainText: control.tiled ? control.tiledText : control.floatingText
        subText: control.interactive && control.pending ? control.waitingText
               : control.interactive && d.notice !== "" ? d.notice
               : control.tiled ? i18nc("@info:tooltip layout control", "The dynamic tiler arranges this workspace's windows")
               : i18nc("@info:tooltip layout control", "The dynamic tiler does not arrange this workspace")

        // The pointer's way in, only while interactive: the read-only control handles no click.
        // Inside the tooltip area, as the date's: a hover item on top would take the hover from it.
        Loader {
            anchors.fill: parent
            active: control.interactive
            sourceComponent: MouseArea {
                // A press then click toggles, as on the date: a press while the menu is open closes
                // it, and the click after it opens nothing. Only the left button, so that a right
                // click still opens the widget's context menu; no wheel, so that the wheel still
                // switches workspaces.
                property bool opens: false

                objectName: "layoutArea"
                acceptedButtons: Qt.LeftButton
                // The control itself is the accessible button.
                Accessible.ignored: true
                onPressed: {
                    opens = !control.menuOpen;
                    if (!opens) {
                        control.menuDismissed();
                    }
                }
                onClicked: {
                    if (opens) {
                        control.menuRequested("pointer");
                    }
                }
            }
        }
    }

    // The Fusion focus ring: 2 px with a 2 px gap outside the control (the Controls board), as
    // the calendar's buttons draw it, round as the pill.
    Rectangle {
        objectName: "layoutFocusRing"
        visible: control.interactive && control.activeFocus
        anchors.fill: parent
        anchors.margins: -4
        radius: height / 2
        antialiasing: true
        color: "transparent"
        border.width: 2
        border.color: control.accent ? control.accent.focusRing : "transparent"
    }

    Row {
        objectName: "layoutContent"
        anchors.verticalCenter: parent.verticalCenter
        spacing: control.gap
        // A choice awaited with the menu closed: drawn at 0.7 until the outcome, as quick settings
        // dims a busy row's status, with no animation and no change of width.
        opacity: control.interactive && control.pending ? 0.7 : 1

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
