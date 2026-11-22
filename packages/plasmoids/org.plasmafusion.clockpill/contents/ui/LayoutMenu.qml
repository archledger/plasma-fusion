/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

// The layout menu that the pill's layout control opens: the Floating and Tiled choices for the
// bar's view, and a status line for their outcome (docs/parts/shell-topbar.md, "The layout menu").
// It decides nothing. Its owner shows it in an applet pop-up of its own, the focus that the
// placement script's prepare accepts, binds it to the layout state (LayoutState.qml) and forwards
// what it reports: an input, of which the first prepares - a navigation or choosing key, or a left
// press on a row, but no auto-repeat, Escape or hover, so that a menu merely open or passed over
// holds nothing of the provider's -; a choice, sent even for the mode shown, as the provider
// decides; and Escape, the user's close.
//
// No board draws it, and its values are the boards': the Controls board's menu rows (32 px,
// radius 8, padding 0 10, Manrope 13 px, 1 px apart, disabled text in text3) and the board menu's
// width (236 px); the TabletPairs board's touch menu (44 px rows, padding 0 12, 14.5 px at 600,
// 250 px wide); and the Gestures board's chosen option as the settings module's drop-down draws
// it: the accent's soft fill, weight 700 and a 16 px check at the trailing edge. The pop-up draws
// the style's dialog frame around it.
FocusScope {
    id: menu

    // The layout state's mode: the confirmed row is that mode's.
    required property string mode
    // Tiled needs an app window to tile, and the prepare found none on a floating view.
    property bool tiledBlocked: false
    // The choice queued or sent, and whether one is awaited: the rows then wait, the chosen one
    // with "…".
    property string choice: ""
    property bool pending: false
    // The outcome to present, worded already (LayoutControl.qml, outcomeText()), or empty.
    property string status: ""
    // Touch rows.
    property bool touch: false
    // The bar's edge: the status line goes on the side away from it, so that a line that appears
    // grows the pop-up away from the bar and moves no row under the pointer.
    property int location: PlasmaCore.Types.TopEdge

    // An input that counts: the first prepares.
    signal inputReported()
    // A choice, tiled or floating.
    signal chosen(string mode)
    // Escape: the user's close.
    signal closeRequested()

    readonly property real rowHeight: m.px(touch ? 44 : 32)
    // The rows' padding, and the gap before the check: the same on each board (10, touch 12).
    readonly property real inset: m.px(touch ? 12 : 10)
    // Between the rows and the status line: the board menu's padding.
    readonly property real statusGap: m.px(6)
    readonly property bool statusAbove: location === PlasmaCore.Types.BottomEdge
    readonly property bool statusShown: status !== ""

    // The scheme's text; the Controls board's secondary and disabled text; the chosen option's
    // fill and text as the settings module's drop-down has them (FusionPalette.qml: the board's
    // shades with the Fusion accent, derived from any other); the window card's hover.
    readonly property bool dark: accent.dark
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color secondaryText: dark ? "#a3abc2" : "#4d546a"
    readonly property color disabledText: dark ? "#6f7892" : "#9aa0b2"
    readonly property color chosenFill: accent.soft(dark ? 0.18 : 0.12)
    readonly property color chosenText: accent.schemeAccent ? (dark ? "#cfe0ff" : "#1d4fb0")
        : dark ? Kirigami.ColorUtils.tintWithAlpha("#ffffff", accent.hoverAccent, 0.3) : Qt.darker(accent.focusRing, 1.45)
    readonly property color hoverFill: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.07)

    // The rows in order, for the keys that move between them.
    readonly property var rowItems: [floatingRow, tiledRow]
    readonly property var navigationKeys: [Qt.Key_Up, Qt.Key_Down, Qt.Key_Home, Qt.Key_End, Qt.Key_Tab, Qt.Key_Backtab]
    readonly property var choosingKeys: [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select]

    // A fixed width: large text widens it, as it goes through the metrics, but "…" and a reason
    // never do; long texts wrap.
    implicitWidth: m.px(touch ? 250 : 236)
    implicitHeight: rows.height + (statusShown ? statusLine.height + statusGap : 0)
    width: implicitWidth
    height: implicitHeight

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    Accessible.role: Accessible.Pane
    Accessible.name: i18nc("@title accessible name of the layout menu", "Dynamic tiling")

    // The text scale, pixel grid and accent of the pop-up's own window.
    FusionMetrics {
        id: m
    }
    FusionAccent {
        id: accent
    }

    // The confirmed row takes focus as the menu opens, so that a screen reader names the mode
    // shown first and one arrow reaches the other choice: with a keyboard reason when the menu
    // was opened by keys or the accessible press action, so that its ring shows, and with a mouse
    // reason for the pointer. A row focused already would keep the reason it had (QQuickItem), so
    // its focus is taken first.
    function focusConfirmed(byKeyboard: bool): void {
        const row = menu.mode === "tiled" ? tiledRow : floatingRow;
        row.focus = false;
        row.forceActiveFocus(byKeyboard ? Qt.TabFocusReason : Qt.MouseFocusReason);
    }

    // Moves focus from the row at `from` by `step` rows, wrapping and skipping a disabled row,
    // with a keyboard reason, so that the ring shows; nothing when no row is enabled.
    function moveFocus(from: int, step: int): void {
        const count = menu.rowItems.length;
        for (let i = 1; i <= count; ++i) {
            const row = menu.rowItems[((from + step * i) % count + count) % count];
            if (row.enabled) {
                row.forceActiveFocus(step < 0 ? Qt.BacktabFocusReason : Qt.TabFocusReason);
                return;
            }
        }
    }

    // A disabled row hands the active focus to its scope, the menu, not to the other row (Qt
    // 6.11's QQuickItem), and keeps its own focus. Once the rows have settled - pending and
    // Tiled's block can change in the same event, in either order - the menu gives the focus to
    // the next enabled row itself, with a keyboard reason (S12). While every row waits the menu
    // keeps it, and the row that had it takes it back as the rows are enabled again. The reason
    // Tiled is blocked is the owner's to present; the menu says nothing of it.
    function keepFocus(): void {
        const at = menu.rowItems.findIndex(row => row.focus);
        if (menu.activeFocus && at !== -1 && !menu.rowItems[at].enabled) {
            menu.moveFocus(at, 1);
        }
    }

    // Up and Down move between the rows and wrap, Home and End go to the first and the last
    // enabled row, and Escape closes. Tab and Backtab go through Qt's Tab chain, which in the
    // pop-up's window holds the rows alone, and wrap there.
    Keys.onPressed: event => {
        const at = menu.rowItems.findIndex(row => row.activeFocus);
        switch (event.key) {
        case Qt.Key_Up:
            menu.moveFocus(at, -1);
            break;
        case Qt.Key_Down:
            menu.moveFocus(at, 1);
            break;
        case Qt.Key_Home:
            menu.moveFocus(menu.rowItems.length - 1, 1);
            break;
        case Qt.Key_End:
            menu.moveFocus(0, -1);
            break;
        case Qt.Key_Escape:
            menu.closeRequested();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    Column {
        id: rows
        y: menu.statusAbove && menu.statusShown ? statusLine.height + menu.statusGap : 0
        width: menu.width
        spacing: 1

        MenuRow {
            id: floatingRow
            mode: "floating"
            text: i18nc("@item:inmenu layout menu, the dynamic tiler does not arrange this workspace", "Floating")
        }
        MenuRow {
            id: tiledRow
            mode: "tiled"
            text: i18nc("@item:inmenu layout menu, the dynamic tiler arranges this workspace's windows", "Tiled")
        }
    }

    // The outcome, in the Controls board's 11.5 px secondary text, as wide as the rows' labels.
    FusionText {
        id: statusLine
        objectName: "layoutMenuStatus"
        visible: menu.statusShown
        x: menu.inset
        y: menu.statusAbove ? 0 : rows.height + menu.statusGap
        width: menu.width - 2 * menu.inset
        metrics: m
        px: 11.5
        color: menu.secondaryText
        wrapMode: Text.Wrap
        // Set, so that a mirrored layout mirrors it.
        horizontalAlignment: Text.AlignLeft
        text: menu.status
    }

    // A choice: a radio row, checked on the confirmed mode, with no glyph, as next to the check a
    // Floating glyph would read as an empty checkbox.
    component MenuRow: T.AbstractButton {
        id: row

        required property string mode
        readonly property bool confirmed: menu.mode === mode
        readonly property bool blocked: mode === "tiled" && menu.tiledBlocked
        readonly property bool waiting: menu.pending && menu.choice === mode

        objectName: "layoutMenu-" + mode
        width: menu.width
        // A long label wraps, and its row grows by the extra lines.
        implicitHeight: menu.rowHeight + labelText.implicitHeight * (labelText.lineCount - 1) / Math.max(1, labelText.lineCount)
        horizontalPadding: menu.inset
        enabled: !menu.pending && !blocked
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus

        Accessible.role: Accessible.RadioButton
        Accessible.name: text
        Accessible.checkable: true
        Accessible.checked: confirmed
        Accessible.description: waiting ? i18nc("@info layout menu, a choice was sent", "Waiting for an answer")
                              : blocked ? menu.status : ""

        // The input first. The navigation keys go on, to the menu's handlers and Qt's Tab chain;
        // the choosing keys stay here, repeated or not, so that the button's own Space handling
        // does not click as well.
        Keys.onPressed: event => {
            const choosing = menu.choosingKeys.indexOf(event.key) !== -1;
            if (!event.isAutoRepeat && (choosing || menu.navigationKeys.indexOf(event.key) !== -1)) {
                menu.inputReported();
                if (choosing) {
                    menu.chosen(row.mode);
                }
            }
            event.accepted = choosing;
        }
        // A left press reports the input, and its release chooses; hover only highlights.
        onPressed: menu.inputReported()
        onClicked: menu.chosen(mode)
        onEnabledChanged: Qt.callLater(menu.keepFocus)

        background: Rectangle {
            objectName: "layoutMenuFill-" + row.mode
            radius: 8
            color: row.confirmed ? menu.chosenFill : row.hovered ? menu.hoverFill : "transparent"

            // The keyboard ring on the row's own edge, as the window card's: the rows are 1 px
            // apart, and a ring outside one would cover its neighbour.
            Rectangle {
                objectName: "layoutMenuRing-" + row.mode
                visible: row.visualFocus
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 2
                border.color: accent.focusRing
            }
        }

        contentItem: Item {
            implicitHeight: labelText.implicitHeight

            FusionText {
                id: labelText
                objectName: "layoutMenuLabel-" + row.mode
                anchors.left: parent.left
                anchors.right: check.visible ? check.left : parent.right
                anchors.rightMargin: check.visible ? menu.inset : 0
                anchors.verticalCenter: parent.verticalCenter
                metrics: m
                px: menu.touch ? 14.5 : 13
                weight: row.confirmed ? 700 : menu.touch ? 600 : 400
                color: !row.enabled ? menu.disabledText : row.confirmed ? menu.chosenText : menu.textColor
                wrapMode: Text.Wrap
                // Set, so that a mirrored layout mirrors it.
                horizontalAlignment: Text.AlignLeft
                text: row.waiting ? i18nc("@item:inmenu layout menu, a choice waiting for its answer", "%1…", row.text) : row.text
            }

            // The Gestures board's check: an SVG path on a 24 x 24 grid, stroked 1.8.
            Item {
                id: check
                objectName: "layoutMenuCheck-" + row.mode

                readonly property string path: "M5 12.5l4.5 4.5L19 7.5"
                readonly property color color: labelText.color

                visible: row.confirmed
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: m.px(16)
                height: m.px(16)

                Shape {
                    width: 24
                    height: 24
                    scale: check.width / 24
                    transformOrigin: Item.TopLeft
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: check.color
                        strokeWidth: 1.8
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: check.path }
                    }
                }
            }
        }
    }
}
