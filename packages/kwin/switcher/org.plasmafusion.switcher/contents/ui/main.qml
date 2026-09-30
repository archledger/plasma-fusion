/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWin
import org.kde.plasma.core as PlasmaCore

// Plasma Fusion window switcher (boards AltTab.dc.html and AltTabLight.dc.html).
//
// Two internal windows: a dim layer over the work area (below the top bar), then the frosted
// card on top of it. The card is created only after the dim layer has shown a frame, so it is
// always stacked above it, and it is declared first so that KWin (which sends key events to
// the first window it finds below this object) talks to the card.
//
// Workspace tabs: the switcher filters KWin's list itself. With kwinrc [TabBox] DesktopMode=0
// (every workspace in the list) "This workspace" and "All workspaces" both work (click or A).
// With DesktopMode=1 the list holds only this workspace and "All workspaces" is disabled.
KWin.TabBoxSwitcher {
    id: tabBox

    Item {
        id: root

        // Text scale and pixel grid of the switcher's screen (docs/parts/kwin.md, "Text scale").
        // Its sizes are needed before the card window exists, so the scale comes from the output.
        FusionMetrics {
            id: fusionMetrics
            screenScale: root.output ? root.output.devicePixelRatio : 0
            area: root.dimArea
        }
        readonly property FusionMetrics metrics: fusionMetrics

        readonly property int cellWidth: 196
        readonly property int thumbnailHeight: 118
        // Board: padding 10, the preview, 10, the caption (34 px of text, scaled with it), 10.
        readonly property real captionHeight: metrics.px(34)
        readonly property real cellHeight: 10 + thumbnailHeight + 10 + captionHeight + 10
        readonly property int gap: 16
        readonly property int maxColumns: 5

        // Filter state, rebuilt whenever the switcher opens or its list changes.
        property bool showAll: false
        property var shownRows: []
        property var shownMap: ({})
        property bool hasOtherWorkspaces: false
        property int lastIndex: -1
        property bool adjusting: false
        property var windowsById: ({})
        property var output: null
        property var desktop: null
        property string desktopName: ""
        property bool dimShown: false
        property bool open: false

        readonly property bool canShowAll: tabBox.allDesktops
        readonly property int shownCount: shownRows.length

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        FusionPalette {
            id: fusionPalette
            dark: {
                const c = Kirigami.Theme.backgroundColor;
                return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
            }
            accent: Kirigami.Theme.highlightColor
        }
        readonly property FusionPalette pal: fusionPalette

        // Row data of KWin's list, independent of the card window's lifetime.
        Instantiator {
            id: rows
            model: tabBox.model
            delegate: QtObject {
                required property var windowId
                required property var caption
                required property var desktopName
            }
            onObjectAdded: Qt.callLater(root.refresh)
            onObjectRemoved: Qt.callLater(root.refresh)
        }

        function keyOf(id) {
            return id === undefined || id === null ? "" : String(id);
        }

        function rebuildWindowMap() {
            const map = {};
            const all = KWin.Workspace.windows;
            for (let i = 0; i < all.length; ++i) {
                map[keyOf(all[i].internalId)] = all[i];
            }
            windowsById = map;
        }

        function windowFor(id) {
            const key = keyOf(id);
            if (key.length === 0) {
                return null;
            }
            let w = windowsById[key];
            if (w === undefined) {
                rebuildWindowMap();
                w = windowsById[key];
            }
            return w === undefined ? null : w;
        }

        function isOnDesktop(w, d) {
            if (!w || !d) {
                return true;
            }
            if (w.onAllDesktops) {
                return true;
            }
            const list = w.desktops;
            for (let i = 0; i < list.length; ++i) {
                if (list[i] === d) {
                    return true;
                }
            }
            return false;
        }

        function updateScreen() {
            const g = tabBox.screenGeometry;
            let out = null;
            try {
                out = KWin.Workspace.screenAt(Qt.point(g.x + g.width / 2, g.y + g.height / 2));
            } catch (e) {
                out = null;
            }
            output = out;
            let d = null;
            try {
                d = out ? KWin.Workspace.currentDesktopForScreen(out) : null;
            } catch (e) {
                d = null;
            }
            desktop = d ? d : KWin.Workspace.currentDesktop;
            desktopName = desktop ? desktop.name : "";
        }

        function refresh() {
            if (!open) {
                return;
            }
            const n = rows.count;
            const list = [];
            const map = {};
            let others = false;
            for (let i = 0; i < n; ++i) {
                const row = rows.objectAt(i);
                if (!row) {
                    continue;
                }
                const onHere = isOnDesktop(windowFor(row.windowId), desktop);
                if (!onHere) {
                    others = true;
                }
                if (showAll || onHere) {
                    list.push(i);
                    map[i] = true;
                }
            }
            hasOtherWorkspaces = others;
            shownRows = list;
            shownMap = map;
            syncSelection(true);
        }

        // Keeps KWin's selection on a visible row. KWin walks through every row of its list;
        // hidden rows are skipped in the direction of travel.
        function syncSelection(force) {
            if (adjusting) {
                return;
            }
            const idx = tabBox.currentIndex;
            if (shownRows.length === 0 || shownMap[idx] === true) {
                lastIndex = idx;
                return;
            }
            const n = rows.count;
            let forward = true;
            if (!force && lastIndex >= 0 && n > 0) {
                const step = (idx - lastIndex + n) % n;
                forward = step <= n / 2;
            }
            const target = nextShown(idx, forward);
            if (target < 0) {
                return;
            }
            adjusting = true;
            tabBox.currentIndex = target;
            adjusting = false;
            lastIndex = target;
        }

        function nextShown(from, forward) {
            const n = rows.count;
            for (let k = 1; k <= n; ++k) {
                const i = forward ? (from + k) % n : (from - k + n * 2) % n;
                if (shownMap[i] === true) {
                    return i;
                }
            }
            return -1;
        }

        function stepSelection(delta) {
            if (shownRows.length === 0) {
                return;
            }
            let pos = shownRows.indexOf(tabBox.currentIndex);
            if (pos < 0) {
                pos = 0;
            }
            const count = shownRows.length;
            let next = pos + delta;
            if (Math.abs(delta) === 1) {
                next = (next + count) % count;
            } else {
                next = Math.max(0, Math.min(count - 1, next));
            }
            lastIndex = shownRows[next];
            tabBox.currentIndex = shownRows[next];
        }

        function setShowAll(value) {
            if (value && !canShowAll) {
                return;
            }
            if (showAll === value) {
                return;
            }
            showAll = value;
            refresh();
        }

        // Keys of the switcher (KWin itself handles Tab, Shift+Tab, ` and Esc). Used by the card
        // and, before the card window exists (its first frame), by the dim layer, which is then
        // the window KWin sends the keys to.
        function handleKey(event) {
            switch (event.key) {
            case Qt.Key_Left:
                stepSelection(-1);
                break;
            case Qt.Key_Right:
                stepSelection(1);
                break;
            case Qt.Key_Up:
                stepSelection(-columns);
                break;
            case Qt.Key_Down:
                stepSelection(columns);
                break;
            case Qt.Key_Home:
                stepSelection(-rows.count);
                break;
            case Qt.Key_End:
                stepSelection(rows.count);
                break;
            case Qt.Key_A:
                setShowAll(!showAll);
                break;
            case Qt.Key_Q:
                if (shownMap[tabBox.currentIndex] === true) {
                    tabBox.model.close(tabBox.currentIndex);
                }
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (shownMap[tabBox.currentIndex] === true) {
                    tabBox.model.activate(tabBox.currentIndex);
                }
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        // "Wallpapers — Dolphin" -> app "Dolphin", title "Wallpapers". The suffix counts as the
        // app name only when it matches the window's application ids.
        function appKeys(w) {
            const keys = [];
            if (!w) {
                return keys;
            }
            const add = s => {
                const k = String(s || "").toLowerCase().replace(/[^a-z0-9]/g, "");
                if (k.length > 1 && keys.indexOf(k) < 0) {
                    keys.push(k);
                }
            };
            const dfn = String(w.desktopFileName || "");
            add(dfn.split(".").pop());
            add(dfn);
            add(w.resourceClass);
            add(w.resourceName);
            return keys;
        }

        function prettyName(w) {
            const known = {
                "systemsettings": "System Settings", "konsole": "Konsole", "dolphin": "Dolphin",
                "kwrite": "KWrite", "kate": "Kate", "discover": "Discover", "firefox": "Firefox",
                "google-chrome": "Google Chrome", "chromium-browser": "Chromium", "spectacle": "Spectacle",
                "okular": "Okular", "gwenview": "Gwenview", "elisa": "Elisa", "ark": "Ark"
            };
            if (!w) {
                return "";
            }
            const dfn = String(w.desktopFileName || "");
            let base = dfn.length > 0 ? dfn.split(".").pop() : String(w.resourceClass || w.resourceName || "");
            base = base.replace(/\.desktop$/, "");
            if (known[base.toLowerCase()] !== undefined) {
                return known[base.toLowerCase()];
            }
            return base.split(/[-_\s]+/).filter(s => s.length > 0)
                       .map(s => s.charAt(0).toUpperCase() + s.slice(1)).join(" ");
        }

        function describe(row) {
            const w = windowFor(row.windowId);
            let caption = w && w.captionNormal ? String(w.captionNormal) : String(row.caption || "");
            let app = "";
            let title = caption;
            const keys = appKeys(w);
            const m = caption.match(/^(.*\S)\s+[—–-]\s+(\S.*)$/);
            if (m) {
                const suffix = m[2].toLowerCase().replace(/[^a-z0-9]/g, "");
                const matches = keys.some(k => suffix.indexOf(k) >= 0 || k.indexOf(suffix) >= 0);
                if (matches) {
                    app = m[2];
                    title = m[1];
                }
            }
            if (app.length === 0) {
                app = prettyName(w);
                if (app.length === 0) {
                    app = caption;
                    title = "";
                }
            }
            if (title === app) {
                title = "";
            }
            // KWin keeps its list (and the role values) when the same windows come back, so
            // the workspace name is read from the window itself.
            let where = String(row.desktopName || "");
            if (w && !w.onAllDesktops && w.desktops.length > 0) {
                where = String(w.desktops[w.desktops.length - 1].name || where);
            }
            if (showAll && w && !isOnDesktop(w, desktop) && where.length > 0) {
                title = title.length > 0 ? title + " \u00b7 " + where : where;
            }
            return { app: app, title: title };
        }

        // Card metrics (board: 1100 px, padding 22/28/20/28, gaps 18, grid gap 16). The gaps
        // between the text rows and the header follow the text size; the card padding does not.
        readonly property int padTop: 23
        readonly property int padSide: 28
        readonly property int padBottom: 21
        readonly property real sectionGap: metrics.px(18)
        readonly property int maxCardWidth: Math.min(1100, tabBox.screenGeometry.width - 64)
        readonly property int columnsFit: Math.max(1, Math.min(maxColumns,
            Math.floor((maxCardWidth - 2 * padSide + gap) / (cellWidth + gap))))
        readonly property int columns: Math.max(1, Math.min(columnsFit, shownCount))
        readonly property int gridRows: Math.max(1, Math.ceil(shownCount / columns))
        readonly property int gridWidth: columns * cellWidth + (columns - 1) * gap
        readonly property real fullGridHeight: gridRows * cellHeight + (gridRows - 1) * gap
        readonly property real headerHeight: metrics.px(32)
        property int hintWidth: 620
        property int hintHeight: 22
        readonly property int chromeHeight: Math.ceil(padTop + headerHeight + 2 * sectionGap + hintHeight + padBottom)
        readonly property real maxGridHeight: {
            const room = Math.floor(tabBox.screenGeometry.height * 0.86) - chromeHeight;
            const fit = Math.max(1, Math.floor((room + gap) / (cellHeight + gap)));
            return fit * cellHeight + (fit - 1) * gap;
        }
        readonly property real gridViewportHeight: shownCount === 0 ? cellHeight : Math.min(fullGridHeight, maxGridHeight)
        readonly property int contentWidth: Math.min(maxCardWidth - 2 * padSide,
            Math.max(shownCount === 0 ? 0 : gridWidth, hintWidth, 520))
        readonly property int cardWidth: contentWidth + 2 * padSide
        readonly property int cardHeight: Math.ceil(chromeHeight + gridViewportHeight)

        // Work area of the switcher's screen: the dim layer leaves the top bar undimmed.
        readonly property rect dimArea: {
            if (!tabBox.visible) {
                return tabBox.screenGeometry;
            }
            try {
                const a = KWin.Workspace.clientArea(KWin.Workspace.MaximizeArea, output, desktop);
                if (a.width > 0 && a.height > 0) {
                    return Qt.rect(a.x, a.y, a.width, a.height);
                }
            } catch (e) {
            }
            return tabBox.screenGeometry;
        }

        Connections {
            target: tabBox
            function onAboutToShow() {
                root.open = true;
                root.updateScreen();
                root.rebuildWindowMap();
                root.showAll = false;
                root.lastIndex = -1;
                root.refresh();
                // Nothing on this workspace: open on "All workspaces" instead of an empty card.
                if (root.shownRows.length === 0 && root.canShowAll && rows.count > 0) {
                    root.showAll = true;
                    root.refresh();
                }
            }
            function onVisibleChanged() {
                if (!tabBox.visible) {
                    root.open = false;
                    root.dimShown = false;
                }
            }
            function onCurrentIndexChanged() {
                if (root.open) {
                    root.syncSelection(false);
                }
            }
        }

        Connections {
            target: KWin.Workspace
            enabled: tabBox.visible
            function onCurrentDesktopChanged() {
                root.updateScreen();
                root.refresh();
            }
        }

        // The card. Declared first: see the comment at the top.
        Instantiator {
            id: cardInstantiator
            active: tabBox.visible && root.dimShown
            delegate: PlasmaCore.Dialog {
                id: cardWindow

                property var frameItem: null
                readonly property real marginLeft: margins.left
                readonly property real marginTop: margins.top
                readonly property real marginRight: margins.right
                readonly property real marginBottom: margins.bottom

                location: PlasmaCore.Types.Floating
                flags: Qt.Popup | Qt.X11BypassWindowManagerHint
                x: tabBox.screenGeometry.x + Math.round((tabBox.screenGeometry.width - root.cardWidth) / 2)
                y: tabBox.screenGeometry.y + Math.max(8, Math.round((tabBox.screenGeometry.height - root.cardHeight) / 2) - 24)
                visible: false
                title: i18nd("plasmafusion", "Window switcher")

                // Use the Plasma style's "launcher" frame (radius 26, the board's card) when the
                // style has it; otherwise the regular dialog frame stays.
                function useCardFrame() {
                    if (frameItem || !contentItem) {
                        return;
                    }
                    const children = contentItem.children;
                    for (let i = 0; i < children.length; ++i) {
                        const background = children[i];
                        if (background === mainItem) {
                            continue;
                        }
                        const inner = background.children;
                        for (let j = 0; j < inner.length; ++j) {
                            const candidate = inner[j];
                            if (candidate.imagePath !== undefined && candidate.prefix !== undefined
                                    && candidate.usedPrefix !== undefined) {
                                candidate.prefix = ["launcher", ""];
                                frameItem = candidate;
                                return;
                            }
                        }
                    }
                }

                Component.onCompleted: {
                    useCardFrame();
                    visible = true;
                    requestActivate();
                }

                onSceneGraphError: () => {
                    // Intentionally empty: QtQuick would otherwise qFatal() on a graphics reset.
                }

                mainItem: FocusScope {
                    id: scope
                    focus: true
                    width: root.cardWidth - cardWindow.marginLeft - cardWindow.marginRight
                    height: root.cardHeight - cardWindow.marginTop - cardWindow.marginBottom

                    Keys.onPressed: event => root.handleKey(event)

                    // Laid out against the window edges, whatever the frame margins are.
                    Item {
                        id: layout
                        x: -cardWindow.marginLeft
                        y: -cardWindow.marginTop
                        width: root.cardWidth
                        height: root.cardHeight

                        Rectangle {
                            // Only when the Plasma style gave the card no background at all.
                            anchors.fill: parent
                            radius: 26
                            visible: cardWindow.marginLeft === 0 && cardWindow.marginTop === 0
                            color: root.pal.cardFill
                            border.width: 1
                            border.color: root.pal.tint(0.12)
                        }

                        // Header: workspace tabs and the window count.
                        Item {
                            id: header
                            x: root.padSide
                            y: root.padTop
                            width: parent.width - 2 * root.padSide
                            height: root.headerHeight

                            Rectangle {
                                id: tabTrack
                                // Board: a 32 px track with 26 px tabs, 3 px inside it.
                                readonly property real inset: (height - root.metrics.px(26)) / 2
                                height: root.headerHeight
                                width: tabRow.width + 2 * inset
                                radius: height / 2
                                color: root.pal.tabTrack

                                Row {
                                    id: tabRow
                                    x: tabTrack.inset
                                    y: tabTrack.inset
                                    spacing: 3

                                    Repeater {
                                        model: [
                                            { all: false, label: i18nd("plasmafusion", "This workspace") },
                                            { all: true, label: i18nd("plasmafusion", "All workspaces") }
                                        ]
                                        delegate: Rectangle {
                                            id: tab
                                            required property var modelData
                                            readonly property bool current: root.showAll === modelData.all
                                            readonly property bool usable: !modelData.all || root.canShowAll
                                            width: tabLabel.implicitWidth + root.metrics.px(28)
                                            height: root.metrics.px(26)
                                            radius: height / 2
                                            color: current ? root.pal.accent
                                                           : (tabArea.containsMouse && usable ? root.pal.hoverFill : "transparent")
                                            opacity: usable ? 1 : 0.45

                                            Accessible.role: Accessible.PageTab
                                            Accessible.name: modelData.label
                                            Accessible.selected: current

                                            Text {
                                                id: tabLabel
                                                anchors.centerIn: parent
                                                text: tab.modelData.label
                                                font.family: root.metrics.family
                                                font.pointSize: root.metrics.font(12) * 0.75
                                                font.weight: tab.current ? Font.ExtraBold : Font.Bold
                                                color: tab.current ? root.pal.tabText : root.pal.tabTextInactive
                                                renderType: Text.QtRendering
                                            }

                                            MouseArea {
                                                id: tabArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: tab.usable
                                                onClicked: root.setShowAll(tab.modelData.all)
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                // A long workspace name is cut short instead of running into the tabs.
                                width: Math.min(implicitWidth, parent.width - tabTrack.width - root.metrics.px(24))
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                horizontalAlignment: Text.AlignRight
                                textFormat: Text.PlainText
                                text: i18ndp("plasmafusion", "%1 window", "%1 windows", root.shownCount)
                                      + " · " + (root.showAll ? i18nd("plasmafusion", "All workspaces") : root.desktopName)
                                font.family: root.metrics.family
                                font.pointSize: root.metrics.font(12.5) * 0.75
                                color: root.pal.textMuted
                                renderType: Text.QtRendering
                            }
                        }

                        // Window grid; scrolls when there are more rows than fit on the screen.
                        Flickable {
                            id: flick
                            x: root.padSide
                            y: header.y + header.height + root.sectionGap
                            width: parent.width - 2 * root.padSide
                            height: root.gridViewportHeight
                            contentWidth: width
                            contentHeight: grid.height
                            clip: contentHeight > height
                            interactive: false
                            boundsBehavior: Flickable.StopAtBounds
                            // Keeps the selected row in view (KWin takes the scroll wheel to move
                            // the selection, so the grid scrolls only with it).
                            contentY: {
                                const overflow = contentHeight - height;
                                if (overflow <= 0) {
                                    return 0;
                                }
                                const pos = Math.max(0, root.shownRows.indexOf(tabBox.currentIndex));
                                const rowTop = Math.floor(pos / root.columns) * (root.cellHeight + root.gap);
                                return Math.max(0, Math.min(overflow, rowTop - (height - root.cellHeight) / 2));
                            }

                            Behavior on contentY {
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }

                            Grid {
                                id: grid
                                x: Math.max(0, Math.round((flick.width - root.gridWidth) / 2))
                                columns: root.columns
                                rowSpacing: root.gap
                                columnSpacing: root.gap

                                Repeater {
                                    model: tabBox.model
                                    delegate: WindowCard {
                                        required property int index
                                        required property var model
                                        readonly property var info: {
                                            // Re-evaluated when the filter or the window map changes.
                                            root.shownMap;
                                            root.windowsById;
                                            const row = rows.objectAt(index);
                                            return row ? root.describe(row) : { app: "", title: "" };
                                        }
                                        visible: root.shownMap[index] === true
                                        width: root.cellWidth
                                        height: root.cellHeight
                                        pal: root.pal
                                        metrics: root.metrics
                                        windowId: model.windowId
                                        icon: model.icon
                                        appName: info.app
                                        title: info.title
                                        closeable: model.closeable === true
                                        selected: index === tabBox.currentIndex
                                        thumbnailHeight: root.thumbnailHeight
                                        onActivated: tabBox.model.activate(index)
                                        onCloseRequested: tabBox.model.close(index)
                                    }
                                }
                            }
                        }

                        Text {
                            x: flick.x
                            y: flick.y
                            width: flick.width
                            height: flick.height
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            visible: root.shownCount === 0
                            text: root.showAll || !root.hasOtherWorkspaces
                                  ? i18ndc("kwin", "@info:placeholder no entries in the task switcher", "No open windows")
                                  : i18nd("plasmafusion", "No windows on this workspace")
                            font.family: root.metrics.family
                            font.pointSize: root.metrics.font(14) * 0.75
                            font.weight: Font.Bold
                            color: root.pal.textMuted
                            renderType: Text.QtRendering
                        }

                        // Key hints.
                        Row {
                            id: hints
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: flick.y + flick.height + root.sectionGap
                            spacing: root.metrics.px(22)
                            onImplicitWidthChanged: root.hintWidth = Math.ceil(implicitWidth)
                            onImplicitHeightChanged: root.hintHeight = Math.ceil(implicitHeight)

                            Hint {
                                pal: root.pal
                                metrics: root.metrics
                                keys: [i18ndc("plasmafusion", "keyboard key", "Tab")]
                                after: i18nd("plasmafusion", "Next")
                            }
                            Hint {
                                pal: root.pal
                                metrics: root.metrics
                                keys: [i18ndc("plasmafusion", "keyboard key", "Shift"), i18ndc("plasmafusion", "keyboard key", "Tab")]
                                after: i18nd("plasmafusion", "Back")
                            }
                            Hint {
                                pal: root.pal
                                metrics: root.metrics
                                keys: ["`"]
                                after: i18nd("plasmafusion", "Same app")
                            }
                            Hint {
                                pal: root.pal
                                metrics: root.metrics
                                keys: [i18ndc("plasmafusion", "keyboard key", "Q")]
                                after: i18nd("plasmafusion", "Close window")
                            }
                            Hint {
                                pal: root.pal
                                metrics: root.metrics
                                before: i18nd("plasmafusion", "Release")
                                keys: [i18ndc("plasmafusion", "keyboard key", "Alt")]
                                after: i18nd("plasmafusion", "to switch")
                            }
                        }
                    }
                }
            }
        }

        // The dim layer: input passes through, so a click outside the card closes the switcher.
        // The window itself stays transparent and a Rectangle carries the tint: KWin composites
        // internal windows as premultiplied, and a translucent window clear colour is not
        // premultiplied (the light tint would turn into opaque white).
        Instantiator {
            id: dimInstantiator
            active: tabBox.visible
            delegate: Window {
                flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint
                       | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
                color: "transparent"
                x: root.dimArea.x
                y: root.dimArea.y
                width: root.dimArea.width
                height: root.dimArea.height
                visible: true
                title: i18nd("plasmafusion", "Window switcher backdrop")
                onFrameSwapped: {
                    if (!root.dimShown) {
                        root.dimShown = true;
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: root.pal.dim
                    // Keys typed before the card exists (at most its first frame) arrive here.
                    // The window never becomes active (it does not take focus), so the item
                    // takes active focus itself, or Qt Quick would not deliver them.
                    focus: true
                    Component.onCompleted: forceActiveFocus()
                    Keys.onPressed: event => root.handleKey(event)
                }
            }
        }

        // Never leave the switcher without its card if the dim layer cannot draw.
        Timer {
            interval: 150
            running: tabBox.visible && !root.dimShown
            onTriggered: root.dimShown = true
        }
    }
}
