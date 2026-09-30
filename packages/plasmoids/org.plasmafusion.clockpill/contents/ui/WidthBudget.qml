/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound
// The bar's other widgets are read through their dynamic members (budgetSaving, plasmoid,
// applet, fullRepresentationItem), which the linter cannot see on QQuickItem.
// qmllint disable missing-property

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg

// The top bar's width budget (ADAPTIVE 5.1, fix 4), run by the clock pill because it sits
// between the bar's two expanding spacers. The pill stays exactly on the middle of the bar
// while each side's widgets fit within W/2 − pill/2 − 24; when a side does not fit, the bar
// collapses step by step, each step on top of the ones before:
//
//   1  the global menu (stock appmenu) becomes its one-button compact view (see below)
//   2  phone and clipboard move into quick settings (the quicksettings widget)
//   3  the app name hides: the logo (tablet: the app icon) only (appname)
//   4  the short date in the pill
//   5  the time only
//   6  quick settings hides the battery %
//   7  the workspace dots hide (the overview still switches workspaces)
//
// Tablet posture starts at step 2 (portrait or a narrow screen: step 5), TABLET 4.3.
//
// The global menu (step 1): Plasma 6.7.5 crashes when the stock appmenu goes from its compact
// view back to its full view after its menu changed (another window, a menu update; private
// sessions t2m E1-E6, ov2). The cause is in Qt 6.11's GridLayout: a removed child stays in the
// layout engine until the layout's next polish, and its size hint reads the engine as it is. A
// full view that is not in the bar (compact: unparented) or hidden (the active window has no
// menu) is not polished, and libplasma reads its size hint when it moves it back into the bar
// (or into the popup, when it preloads a compact applet a few seconds after start): a deleted
// item. So the budget rebuilds the full view's layout itself (`ensurePolished()`) right before
// it switches the menu either way, and at once after a menu change while the full view is not
// shown. Private sessions ov6a/b: a change while compact, then full, crashed without the
// rebuild and never with it. `menuPolicy`
// "centre" (the default, ADAPTIVE 5.1) compacts it as the first step whenever the pill cannot
// stay centred with it; "overlap" compacts it only when the bar would otherwise overlap: the
// pill may then leave the middle, and the menu is compacted far less often.
//
// The level is computed in one go, never by trying: every widget of the bar that takes part
// has `budgetLevel` (written here) and `budgetSaving(level)`, the width it gives up at that
// level against level 0. From the bar as it is now and the savings at each widget's current
// level, the level-0 widths follow, and from them the first level at which both sides fit. So
// a change of level never has to be laid out to be judged, and the bar does not flicker. The
// stock global menu has no such hooks: its full width is measured here from its menu model
// (the titles in the panel font and the menubaritem margins), corrected by the difference seen
// the last time its full view was shown.
Item {
    id: budget

    // The clock pill (its root item: `pillWidth`, `pillItem`, `budgetLevel`, `budgetSaving()`).
    required property Item clock
    required property FusionMetrics metrics
    required property bool tablet
    // The clock pill's cell in the panel's layout.
    property Item cell: null
    // Off: level 0 (tablet minimum only); a menu this coordinator compacted goes back when safe.
    property bool active: true
    // Whether this coordinator switched the global menu to compact (the clock pill's config),
    // so that it switches it back; a compact menu the user chose is left alone.
    property bool menuCompacted: false
    signal menuCompactedWritten(bool compacted)
    // "centre" or "overlap" (see the header).
    property string menuPolicy: "centre"

    readonly property int maxLevel: 7
    readonly property int minLevel: !tablet ? 0 : (metrics.portrait || metrics.compactWidth ? 5 : 2)
    readonly property real gap: metrics.px(24)
    // The smallest distance between two widgets when the pill has left the middle.
    readonly property real minimumGap: metrics.px(8)
    property int level: 0

    readonly property GridLayout panelLayout: cell && cell.parent instanceof GridLayout ? cell.parent as GridLayout : null

    // ---- The global menu
    readonly property Item menuApplet: {
        const layout = panelLayout;
        if (!layout) {
            return null;
        }
        for (const child of layout.children) {
            if (child.applet?.plasmoid?.pluginName === "org.kde.plasma.appmenu") {
                return child.applet;
            }
        }
        return null;
    }
    readonly property bool menuCompact: menuApplet ? menuApplet.plasmoid.configuration.compactView === true : false
    readonly property bool menuUserCompact: menuCompact && !menuCompacted
    // Width of the compact menu button, last seen (default: a square button of the bar's row).
    property real compactMenuWidth: metrics.px(34)
    // Measured full view minus the model estimate, last seen.
    property real menuCorrection: 0
    // Menu changes counted by the delegates below.
    property int menuGeneration: 0
    // The full view while it is in the bar and visible (the applet hides it when the active
    // window has no menu; compact, it is unparented, so nothing polishes it).
    readonly property Item fullView: menuApplet ? menuApplet.fullRepresentationItem : null
    readonly property bool fullShown: fullView !== null && !menuCompact && fullView.visible && fullView.parent !== null
    onMenuGenerationChanged: {
        if (!fullShown) {
            Qt.callLater(refreshFullView);
        }
    }
    // Rebuilds the cached full view's layout now (see the header).
    function refreshFullView(): bool {
        const view = fullView;
        if (!view || typeof view.ensurePolished !== "function") {
            return false;
        }
        view.ensurePolished();
        return true;
    }
    // Going back to the full view is safe when its layout can be rebuilt first (Qt 6.3 and later);
    // otherwise the menu stays compact until plasmashell starts again.
    readonly property bool menuExpandSafe: !menuApplet || !fullView || typeof fullView.ensurePolished === "function"
    property bool stuckReported: false

    KSvg.FrameSvgItem {
        id: menuItemFrame
        visible: false
        imagePath: "widgets/menubaritem"
        prefix: "normal"
    }
    // The menu model, as the applet's own full view uses it (rows only while it is visible).
    readonly property var menuModel: menuApplet && menuApplet.plasmoid.model && menuApplet.plasmoid.model.visible
        ? menuApplet.plasmoid.model : null
    Repeater {
        id: menuTitles
        model: budget.menuModel
        delegate: Item {
            id: title
            required property string activeMenu
            required property var activeActions
            readonly property real advance: activeMenu !== "" && (activeActions?.visible ?? false)
                ? Math.ceil(titleMetrics.advanceWidth) + menuItemFrame.margins.left + menuItemFrame.margins.right : 0
            visible: false
            onAdvanceChanged: Qt.callLater(budget.measureMenu)
            Component.onCompleted: {
                budget.menuGeneration++;
                Qt.callLater(budget.measureMenu);
            }
            Component.onDestruction: {
                budget.menuGeneration++;
                Qt.callLater(budget.measureMenu);
            }
            TextMetrics {
                id: titleMetrics
                font: Kirigami.Theme.defaultFont
                // Mnemonic markers are not drawn.
                text: title.activeMenu.replace(/&(.)/g, "$1")
            }
        }
    }
    // The full menu's width from its model. The model is reset when another window becomes
    // active, often with the same number of rows: the delegates report, a binding over
    // itemAt() would not see the new ones.
    property real menuEstimate: 0
    function measureMenu() {
        let width = 0;
        for (let i = 0; menuModel && i < menuTitles.count; ++i) {
            const item = menuTitles.itemAt(i);
            width += item ? item.advance : 0;
        }
        menuEstimate = Math.ceil(width);
    }
    onMenuModelChanged: {
        menuGeneration++;
        Qt.callLater(measureMenu);
    }

    // ---- Reading the bar
    // The spacer's own size hint (org.kde.plasma.panelspacer, optimalSize): what the layout
    // centres by.
    function hint(child: Item): real {
        return Math.min(child.Layout.maximumWidth, Math.max(child.Layout.minimumWidth, child.Layout.preferredWidth))
            + (panelLayout ? panelLayout.columnSpacing : 0);
    }
    function isExpandingSpacer(child: Item): bool {
        return child.applet?.plasmoid?.pluginName === "org.kde.plasma.panelspacer"
            && child.applet.plasmoid.configuration.expanding === true;
    }
    function saving(applet: Item, at: int): real {
        return applet && typeof applet.budgetSaving === "function" ? applet.budgetSaving(at) : 0;
    }
    // A widget's width at budget level `at` (the menu: full or compact).
    function widthAt(c: var, at: int, menuFull: bool): real {
        if (menuApplet && c.applet === menuApplet) {
            const spacing = panelLayout ? panelLayout.columnSpacing : 0;
            return spacing + (menuFull ? Math.max(0, menuEstimate + menuCorrection) : compactMenuWidth);
        }
        const now = c.applet && c.applet.budgetLevel !== undefined ? c.applet.budgetLevel : level;
        return c.hint + saving(c.applet, now) - saving(c.applet, at);
    }

    // Everything the result depends on, read in one binding so that any change re-evaluates:
    // the children and their hints, the window width, the menu estimate and the posture.
    readonly property var snapshot: {
        const layout = panelLayout;
        if (!layout || !clock.Window.window) {
            return null;
        }
        const children = [];
        for (const child of layout.children) {
            if (!child.visible || child.isAppletContainer !== true) {
                continue;
            }
            children.push({ "item": child, "applet": child.applet ?? null, "hint": hint(child), "spacer": isExpandingSpacer(child) });
        }
        return {
            "children": children,
            "windowWidth": clock.Window.window.width,
            "pill": clock.pillWidth,
            "menu": menuEstimate,
            "compact": menuCompact,
            "tablet": tablet,
            "min": minLevel,
            "active": active,
            "policy": menuPolicy
        };
    }
    onSnapshotChanged: Qt.callLater(evaluate)

    function evaluate() {
        const s = snapshot;
        if (!s) {
            return;
        }
        // The two sides: before the first and after the last expanding spacer.
        let first = -1, last = -1;
        for (let i = 0; i < s.children.length; ++i) {
            if (s.children[i].spacer) {
                if (first < 0) {
                    first = i;
                }
                last = i;
            }
        }
        const left = first < 0 ? [] : s.children.slice(0, first), right = last < 0 ? [] : s.children.slice(last + 1);
        const hasMenu = menuApplet !== null && left.concat(right).some(c => c.applet === menuApplet);

        // The menu's measured widths, seen now (the full view corrects the estimate).
        if (hasMenu) {
            const menu = left.concat(right).find(c => c.applet === menuApplet);
            const shown = menu.hint - panelLayout.columnSpacing;
            if (menuCompact) {
                compactMenuWidth = shown;
            } else if (menuEstimate > 0) {
                menuCorrection = shown - menuEstimate;
            }
        }
        // A full menu with no menu for the active window hides itself: then there is nothing
        // to decide about it ("keep").
        if (first < 0 || first === last || !active) {
            apply(minLevel, hasMenu && menuCompacted && menuExpandSafe ? "full" : "keep", "no budget");
            return;
        }

        const sum = (side, at, menuFull) => side.reduce((total, c) => total + widthAt(c, at, menuFull), 0);
        // The layout's own margins at both screen edges.
        const origin = panelLayout.mapToItem(null, 0, 0).x;
        const leftEdge = origin, rightEdge = s.windowWidth - origin - panelLayout.width;
        const pill0 = s.pill + clock.budgetSaving(clock.budgetLevel);
        const pillAt = at => pill0 - clock.budgetSaving(at);
        const measure = (at, menuFull) => ({
            "pill": pillAt(at),
            "left": leftEdge + sum(left, at, menuFull),
            "right": rightEdge + sum(right, at, menuFull)
        });
        const centred = m => {
            const room = s.windowWidth / 2 - m.pill / 2 - gap;
            return m.left <= room && m.right <= room;
        };
        const apart = m => m.left + m.pill + m.right + 2 * minimumGap <= s.windowWidth;
        const describe = (m, menuFull) => "W " + s.windowWidth + ", pill " + Math.round(m.pill) + ", left " + Math.round(m.left)
            + ", right " + Math.round(m.right) + ", menu " + (hasMenu ? (menuFull ? "full" : "compact") : "none");

        // With the full menu (when it may be full): centred at the tablet minimum (the later
        // steps come after the menu's in the order), or with the "overlap" policy apart there;
        // otherwise the compact menu, centred at the first step that does it.
        const fullAllowed = hasMenu && !menuUserCompact && (!menuCompact || menuExpandSafe);
        if (!fullAllowed && hasMenu && menuCompacted && !menuExpandSafe && !stuckReported) {
            stuckReported = true;
            console.info("clockpill: width budget: the global menu stays compact until plasmashell starts again"
                         + " (Plasma 6.7.5 crashes when its compact view goes back after a menu change)");
        }
        const tries = hasMenu && fullAllowed ? [true, false] : [false];
        const menuState = full => !hasMenu ? "keep" : full ? "full" : "compact";
        for (const menuFull of tries) {
            for (let at = minLevel; at <= (menuFull ? minLevel : maxLevel); ++at) {
                const m = measure(at, menuFull);
                if (centred(m)) {
                    apply(at, menuState(menuFull), describe(m, menuFull) + ", centred");
                    return;
                }
            }
            const m = measure(minLevel, menuFull);
            if (menuFull && menuPolicy === "overlap" && apart(m)) {
                apply(minLevel, "full", describe(m, true) + ", pill off the middle");
                return;
            }
        }
        // Nothing fits: every step (the pill may move; the right cluster keeps its minimum).
        apply(maxLevel, menuState(false), describe(measure(maxLevel, false), false) + ", all steps");
    }

    // Guards against a measuring error that flips between two levels: more than six changes
    // within two seconds hold the higher level for five seconds.
    property int changes: 0
    property bool held: false
    Timer {
        id: changeWindow
        interval: 2000
        onTriggered: budget.changes = 0
    }
    Timer {
        id: holdTimer
        interval: 5000
        onTriggered: {
            budget.held = false;
            Qt.callLater(budget.evaluate);
        }
    }

    // `menu`: "full", "compact" or "keep" (leave the global menu as it is).
    function apply(wanted: int, menu: string, report: string) {
        if (held && wanted < level) {
            return;
        }
        const menuChange = menuApplet !== null && !menuUserCompact && menu !== "keep" && (menu === "full") === menuCompact;
        if (wanted !== level || menuChange) {
            if (++changes > 6) {
                held = true;
                holdTimer.restart();
                console.info("clockpill: width budget held at step " + Math.max(level, wanted) + " (level changes too often)");
                wanted = Math.max(level, wanted);
                menu = "keep";
            }
            changeWindow.restart();
            console.info("clockpill: width budget step " + level + " -> " + wanted + " (" + report + ")");
            level = wanted;
        }
        const layout = panelLayout;
        for (const child of layout ? layout.children : []) {
            const applet = child.applet;
            if (applet && applet !== clock && applet.budgetLevel !== undefined && applet.budgetLevel !== level) {
                applet.budgetLevel = level;
            }
        }
        clock.budgetLevel = level;
        if (menu !== "keep") {
            setMenuCompact(menu === "compact");
        }
    }

    // Switches the stock global menu between its full and compact views (its own config key),
    // after the current layout pass, and back only while that is safe (see the header).
    function setMenuCompact(compact: bool) {
        if (!menuApplet || menuUserCompact || compact === menuCompact) {
            return;
        }
        if (!compact && (!menuCompacted || !menuExpandSafe)) {
            return;
        }
        menuWrite.compact = compact;
        menuWrite.restart();
    }
    Timer {
        id: menuWrite
        property bool compact: false
        interval: 0
        onTriggered: {
            const applet = budget.menuApplet;
            if (!applet || applet.plasmoid.configuration.compactView === compact || (!compact && !budget.menuExpandSafe)) {
                return;
            }
            // libplasma reads the full view's size hint while it moves it (see the header).
            const rebuilt = budget.refreshFullView();
            console.info("clockpill: width budget: global menu " + (compact ? "compact" : "full")
                         + (rebuilt ? " (full view rebuilt)" : ""));
            budget.menuCompactedWritten(compact);
            applet.plasmoid.configuration.compactView = compact;
        }
    }

    // The bar as laid out (the tests' view): every widget's x and width in the panel window
    // (and its size hint), the pill's offset from the window's middle.
    function dump(tag: string) {
        const layout = panelLayout;
        const window = clock.Window.window;
        if (!layout || !window) {
            console.info("clockpill: bar " + tag + ": no panel layout");
            return;
        }
        const parts = [];
        for (const child of layout.children) {
            if (!child.visible || child.isAppletContainer !== true) {
                continue;
            }
            const x = child.mapToItem(null, 0, 0).x;
            const name = String(child.applet?.plasmoid?.pluginName ?? "?").replace(/^org\.(kde\.plasma|plasmafusion)\./, "");
            parts.push(name + " " + Math.round(x) + "+" + Math.round(child.width) + " (hint " + Math.round(hint(child) - layout.columnSpacing) + ")");
        }
        const pill = clock.pillItem;
        const px = pill.mapToItem(null, 0, 0).x;
        console.info("clockpill: bar " + tag + ": W " + window.width + ", step " + level + ", menu "
                     + (menuCompact ? "compact" : "full") + " (estimate " + menuEstimate + ", correction " + Math.round(menuCorrection)
                     + ", expand " + (menuExpandSafe ? "safe" : "unsafe") + "), pill " + Math.round(px) + "+" + Math.round(pill.width)
                     + " (offset " + (px + pill.width / 2 - window.width / 2).toFixed(1) + "), " + parts.join(", "));
    }
}
