/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kirigami as Kirigami

import "../code/launcher.js" as Launcher

PlasmoidItem {
    id: root

    // The panel shows the button inline; the menu is a separate window (LauncherWindow)
    // so that it can be centred on the screen instead of anchored to the applet.
    preferredRepresentation: fullRepresentation
    compactRepresentation: null
    fullRepresentation: LauncherButton {
        launcher: root
    }
    switchWidth: 0
    switchHeight: 0
    hideOnWindowDeactivate: true
    activationTogglesExpanded: true

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.icon: "start-here-kde-symbolic"
    toolTipMainText: i18nc("@info:tooltip", "Start")
    toolTipSubText: i18nc("@info:tooltip", "Apps, recent files and search")

    readonly property bool designLabels: Plasmoid.configuration.designLabels
    readonly property bool showRecommended: Plasmoid.configuration.showRecommended
    readonly property bool menuOpen: launcherWindow.visible || sheetWindow.visible
    // Tablet posture: the full-screen sheet instead of the card (TABLET 4.5).
    readonly property bool tablet: tabletState.tablet
    FusionTablet {
        id: tabletState
    }
    Motion {
        id: motion
    }
    property string searchText: ""
    property var chips: [{ key: "all", label: i18nc("@title:tab all applications", "All"), row: -1 }]
    property double lastClosed: 0
    property int seedAttempts: 0

    // BEGIN models (the same ones Kickoff and Kicker use)
    readonly property Kicker.RootModel rootModel: Kicker.RootModel {
        autoPopulate: false
        appletInterface: root
        appNameFormat: 0
        flat: true
        sorted: true
        showSeparators: false
        showRootSeparator: false
        showTopLevelItems: true
        showAllApps: true
        showAllAppsCategorized: false
        showRecentApps: false
        showRecentDocs: false
        showRecentFolders: false
        showPowerSession: false
        showFavoritesPlaceholder: false
        highlightNewlyInstalledApps: false

        onRefreshed: root.modelsRefreshed()

        Component.onCompleted: {
            (favoritesModel as Kicker.KAStatsFavoritesModel).initForClient(Plasmoid.configuration.favoritesClientId);
        }
    }

    readonly property Kicker.KAStatsFavoritesModel favoritesModel: rootModel.favoritesModel as Kicker.KAStatsFavoritesModel

    readonly property Kicker.RunnerModel runnerModel: Kicker.RunnerModel {
        appletInterface: root
        mergeResults: true
        // No web or network runners (decision 6, S10).
        runners: Launcher.searchRunners
        favoritesModel: root.favoritesModel
        query: root.searchText
    }

    readonly property Kicker.RecentUsageModel recentDocsModel: Kicker.RecentUsageModel {
        favoritesModel: root.favoritesModel
        shownItems: Kicker.RecentUsageModel.OnlyDocs
        ordering: Kicker.RecentUsageModel.Recent
    }
    // END models

    function allAppsModel() {
        const model = rootModel.count > 0 ? rootModel.modelForRow(0) : null;
        return model && model.description === "KICKER_ALL_MODEL" ? model : null;
    }

    // Category chips: "All" plus the XDG menu categories that have apps, in the board's order,
    // one chip per category kind.
    Instantiator {
        id: categoryReader
        model: root.rootModel
        delegate: QtObject {
            required property int index
            required property var decoration
            required property bool hasChildren
        }
    }

    // Starts an installed app by its desktop file id ("org.kde.kcalc.desktop") the way a tap in the
    // sheet does (in plasmashell, so it needs no session manager). The dock's split uses it for apps
    // the dock does not have. The index is built for the call only.
    Instantiator {
        id: appIndex
        active: false
        model: root.allAppsModel()
        delegate: QtObject {
            required property string favoriteId
            required property int index
        }
    }
    // An app's desktop file id for a split ("" for anything else).
    function splitAppId(favoriteId: string): string {
        const id = Launcher.appId(favoriteId);
        return /^[A-Za-z0-9._-]+\.desktop$/.test(id) ? id : "";
    }
    // The dock in this panel splits the screen; the sheet closes first, so that the app under it is
    // active again and takes the other half.
    function requestSplit(side: string, appId: string): void {
        if (appId === "") {
            return;
        }
        console.info("launcher: split request: " + appId + " to the " + side);
        closeSheet();
        splitAfterClose.side = side;
        splitAfterClose.appId = appId;
        splitAfterClose.restart();
    }
    Timer {
        id: splitAfterClose
        property string side: ""
        property string appId: ""
        interval: 250
        onTriggered: {
            const layout = root.parent ? root.parent.parent : null;
            for (const child of layout ? layout.children : []) {
                const applet = child ? child["applet"] : null;
                if (applet && applet["plasmoid"] && applet["plasmoid"].pluginName === "org.plasmafusion.dock"
                        && typeof applet["startSplitForApp"] === "function") {
                    applet["startSplitForApp"](appId, side);
                    return;
                }
            }
            console.warn("launcher: split request: no Plasma Fusion dock in this panel");
        }
    }
    function launchApp(appId: string): bool {
        const model = allAppsModel();
        if (!model || appId === "") {
            return false;
        }
        appIndex.active = true;
        let row = -1;
        for (let i = 0; i < appIndex.count; ++i) {
            const entry = appIndex.objectAt(i);
            if (entry && Launcher.appId(entry.favoriteId) === appId) {
                row = entry.index;
                break;
            }
        }
        appIndex.active = false;
        return row >= 0 && model.trigger(row, "", null);
    }

    function rebuildChips() {
        const found = [];
        const seen = {};
        for (let i = 0; i < categoryReader.count; ++i) {
            const entry = categoryReader.objectAt(i);
            if (!entry || !entry.hasChildren || i === 0) {
                continue;
            }
            const label = rootModel.labelForRow(i);
            const key = Launcher.categoryKey(String(entry.decoration || ""), label);
            if (!key || key === "other" || seen[key]) {
                continue;
            }
            const model = rootModel.modelForRow(i);
            if (!model || model.count === 0) {
                continue;
            }
            seen[key] = true;
            found.push({ key: key, label: label, row: i, rank: Launcher.categoryRank(key) });
        }
        found.sort((a, b) => a.rank - b.rank || a.label.localeCompare(b.label));
        chips = [{ key: "all", label: i18nc("@title:tab all applications", "All"), row: -1 }].concat(found);
    }

    // Default pins: one installed app per slot of the configured list, written once (first run)
    // to the KActivities store. Pins are shared with every launcher (Kickoff too); apps that were
    // already pinned stay, after the design's set.
    Instantiator {
        id: installedReader
        active: !Plasmoid.configuration.favoritesPortedToKAstats
        model: root.allAppsModel()
        delegate: QtObject {
            required property string favoriteId
        }
    }

    // The current pins, to put the design's set first without duplicating existing ones.
    Instantiator {
        id: pinnedReader
        active: !Plasmoid.configuration.favoritesPortedToKAstats
        model: root.favoritesModel
        delegate: QtObject {
            required property string favoriteId
        }
    }

    function seedFavorites() {
        if (Plasmoid.configuration.favoritesPortedToKAstats || !favoritesModel) {
            return;
        }
        // Keyed by the plain desktop id (Launcher.appId), valued with the id in the model's own
        // form, which is the form to pin with (Plasma 6.7 and 6.8 differ).
        const installed = {};
        for (let i = 0; i < installedReader.count; ++i) {
            const entry = installedReader.objectAt(i);
            if (entry && entry.favoriteId) {
                installed[Launcher.appId(entry.favoriteId)] = String(entry.favoriteId);
            }
        }
        if (Object.keys(installed).length === 0) {
            // The app list is not ready yet.
            if (++seedAttempts < 15) {
                seedRetry.restart();
            }
            return;
        }
        // The current pins (read before the flag below deactivates the readers). A pinned app
        // counts as installed even when the menu does not list it.
        // current: the pins as the model names them; currentKeys: the same as plain desktop ids.
        const current = [];
        for (let i = 0; i < pinnedReader.count; ++i) {
            const entry = pinnedReader.objectAt(i);
            current.push(entry ? String(entry.favoriteId) : "");
        }
        const currentKeys = current.map(id => Launcher.appId(id));
        const pinnedAs = id => {
            const row = currentKeys.indexOf(Launcher.appId(id));
            return row >= 0 ? current[row] : (installed[Launcher.appId(id)] || id);
        };
        const ids = [];
        const duplicates = [];
        for (const slot of Launcher.pinnedSlots(Plasmoid.configuration.favorites)) {
            const pick = slot.find(id => id.indexOf("preferred://") === 0 || installed[Launcher.appId(id)]
                                         || currentKeys.indexOf(Launcher.appId(id)) >= 0);
            if (pick) {
                ids.push(pinnedAs(pick));
                // Another app for the same slot would show a second tile for the same role
                // (Fedora pins Kontact next to KMail, GNOME Files next to Dolphin).
                duplicates.push(...slot.filter(id => Launcher.appId(id) !== Launcher.appId(pick)
                                                     && currentKeys.indexOf(Launcher.appId(id)) >= 0).map(pinnedAs));
            }
        }
        Plasmoid.configuration.favoritesPortedToKAstats = true;

        // Not portOldFavorites(): it replaces the given list with the distribution's
        // kicker-extra-favoritesrc when that sets IgnoreDefaults (Fedora does), so the design's
        // set would never be pinned. Insert or move each pin to its place instead; pins that
        // existed before stay after the design's set.
        let place = 0;
        for (const id of ids) {
            const row = current.indexOf(id);
            if (row < 0 && !favoritesModel.isFavorite(id)) {
                favoritesModel.addFavorite(id, place);
                if (!favoritesModel.isFavorite(id)) {
                    continue; // not a valid entry here
                }
                current.splice(place, 0, id);
            } else if (row >= 0 && row !== place) {
                favoritesModel.moveRow(row, place);
                current.splice(place, 0, current.splice(row, 1)[0]);
            } else if (row < 0) {
                continue; // pinned under another id form; leave it where it is
            }
            ++place;
        }
        for (const id of duplicates) {
            if (favoritesModel.isFavorite(id)) {
                favoritesModel.removeFavorite(id);
            }
        }
    }

    Timer {
        id: seedRetry
        interval: 2000
        onTriggered: root.seedFavorites()
    }

    function modelsRefreshed() {
        Qt.callLater(rebuildChips);
        Qt.callLater(seedFavorites);
    }

    // BEGIN open and close
    function screenArea() {
        const screen = root.screenGeometry;
        const avail = root.availableScreenRect;
        return {
            x: screen.x,
            y: screen.y,
            width: screen.width,
            height: screen.height,
            availTop: screen.y + avail.y,
            availBottom: screen.y + avail.y + avail.height,
            availLeft: screen.x + avail.x,
            availWidth: avail.width,
            availHeight: avail.height,
        };
    }

    // Card: 680 px wide, centred on the screen; its bottom edge sits `bottomOffset` px above the
    // screen bottom (board: 16 px dock gap + 74 px dock + 18 px) or, when a bottom panel reserves
    // more room, 4 px above that panel's reserved area (a floating panel's reserved area already
    // includes its floating gap, 16 px in the Plasma Fusion style). Width and height limits
    // follow the user's text size (at most the screen width less 32 px), rounded to whole
    // device pixels of the window's screen.
    //
    // Height (ADAPTIVE 5.6): clamp(0.78 H, 420, 700) scaled with the text, or 960 in portrait (five
    // pinned rows), never more than the room between the top bar and the dock. `area` is another
    // screen's (the active one, openOn()); there is no dock there. An on-screen keyboard pushes the
    // card up (Qt's keyboard rectangle; without one while KWin shows its keyboard, the lower 40 %).
    function placeWindows(area) {
        const s = area || screenArea();
        const m = launcherWindow.metrics;
        let bottom = area ? s.y + s.height - 24 : Math.min(s.y + s.height - Plasmoid.configuration.bottomOffset, s.availBottom - 4);
        // qmllint disable missing-property
        const keyboard = Qt.inputMethod.keyboardRectangle;
        if (keyboard.height > 0) {
            bottom = Math.min(bottom, s.y + keyboard.y - 8);
        } else if (Qt.inputMethod.visible) {
            bottom = Math.min(bottom, s.y + Math.round(s.height * 0.6) - 8);
        }
        // qmllint enable missing-property
        const top = s.availTop + 8;
        const portrait = s.height > s.width;
        const wanted = portrait ? m.px(960) : Math.max(m.px(420), Math.min(m.px(700), 0.78 * s.height));
        const height = Math.max(Math.min(m.px(420), bottom - top), Math.min(wanted, bottom - top));
        launcherWindow.cardWidth = m.windowSize(Math.min(m.px(680), s.width - 32));
        launcherWindow.cardHeight = m.windowSize(height);
        launcherWindow.x = Math.round(s.x + (s.width - launcherWindow.cardWidth) / 2);
        launcherWindow.y = Math.round(Math.max(top, bottom - height));
        // The dim layer covers the whole screen; panels stay above it (they are in a higher layer).
        backdrop.area = Qt.rect(s.x, s.y, s.width, s.height);
    }
    Connections {
        target: Qt.inputMethod
        function onKeyboardRectangleChanged() {
            if (launcherWindow.visible) {
                root.placeWindows();
            }
        }
    }

    // The card is built on idle; an open request before that waits for it.
    property var pendingOpen: null
    property real openStarted: 0
    property bool firstShown: false
    function prepareCard() {
        launcherWindow.cardWanted = true;
    }
    Timer {
        // 4 s after start (3-5 s, BACKLOG S2).
        interval: 4000
        running: !launcherWindow.cardWanted
        onTriggered: root.prepareCard()
    }
    Connections {
        target: launcherWindow
        function onCardReady() {
            if (root.pendingOpen) {
                const request = root.pendingOpen;
                root.pendingOpen = null;
                root.open(request.mode, request.argument);
            }
        }
    }

    // Opens on the active screen (M18): with several screens KWin names it first.
    function open(mode, argument) {
        if (tablet) {
            openSheet(mode, argument, true);
            return;
        }
        if (openStarted === 0) {
            openStarted = Date.now();
        }
        if (!launcherWindow.card) {
            prepareCard();
            pendingOpen = { "mode": mode, "argument": argument };
            return;
        }
        // qmllint disable missing-property
        const screens = Qt.application.screens;
        // qmllint enable missing-property
        if (screens.length > 1) {
            DBus.SessionBus.asyncCall({
                "service": "org.kde.KWin",
                "path": "/KWin",
                "iface": "org.kde.KWin",
                "member": "activeOutputName",
                "arguments": []
            }, reply => root.openOn(mode, argument, String(reply.value || "")), () => root.openOn(mode, argument, ""));
            return;
        }
        openOn(mode, argument, "");
    }
    function openOn(mode, argument, output) {
        let area = null;
        const own = root.screenGeometry;
        // qmllint disable missing-property
        for (const screen of Qt.application.screens) {
            if (output !== "" && screen.name === output && (screen.virtualX !== own.x || screen.virtualY !== own.y)) {
                // Another screen than the applet's: its top bar is as tall as this one's.
                const topBar = root.availableScreenRect.y;
                area = {
                    x: screen.virtualX, y: screen.virtualY, width: screen.width, height: screen.height,
                    availTop: screen.virtualY + topBar, availBottom: screen.virtualY + screen.height,
                    availLeft: screen.virtualX, availWidth: screen.width, availHeight: screen.height - topBar
                };
            }
        }
        // qmllint enable missing-property
        placeWindows(area);
        launcherWindow.card.openMode(mode || "home", argument || "");
        if (Plasmoid.configuration.dimBackground) {
            const light = !launcherWindow.card.pal.dark;
            backdrop.dimColor = light ? Qt.rgba(221 / 255, 230 / 255, 244 / 255, 0.35) : Qt.rgba(6 / 255, 8 / 255, 18 / 255, 0.4);
            backdrop.visible = true;
        }
        launcherWindow.visible = true;
        launcherWindow.requestActivate();
        launcherWindow.card.forceActiveFocus();
        syncExpanded();
    }

    function close() {
        if (sheetWindow.visible) {
            closeSheet();
        }
        launcherWindow.visible = false;
    }

    function toggle() {
        if (menuOpen) {
            close();
        } else {
            open("home");
        }
    }

    // True while the menu is open or was closed a moment ago (a click on the panel button can
    // deactivate and close the menu before the click itself arrives).
    function recentlyOpen() {
        return menuOpen || (Date.now() - lastClosed) < 300;
    }

    // BEGIN tablet sheet
    // The sheet is built in the background when tablet posture starts, or on its first use.
    property var pendingSheet: null
    Timer {
        interval: 3000
        running: root.tablet && !sheetWindow.sheetWanted
        onTriggered: sheetWindow.sheetWanted = true
    }
    property real sheetStarted: 0
    property int sheetFrames: 0
    function openSheet(mode, argument, animated) {
        if (!sheetWindow.sheet) {
            sheetWindow.sheetWanted = true;
            pendingSheet = { "mode": mode, "argument": argument, "animated": animated };
            return;
        }
        const s = screenArea();
        sheetWindow.area = Qt.rect(s.x, s.y, s.width, s.height);
        sheetWindow.topBar = Math.max(0, root.availableScreenRect.y);
        sheetWindow.screenNumber = Plasmoid.containment ? Plasmoid.containment.screen : 0;
        const sheet = sheetWindow.sheet;
        sheetAnimation.stop();
        if (!sheetWindow.visible) {
            sheet.reset();
            sheet.progress = 0;
        }
        sheetStarted = Date.now();
        sheetFrames = 0;
        sheetWindow.visible = true;
        sheetWindow.requestActivate();
        sheet.forceActiveFocus();
        if (mode === "search") {
            sheet.focusSearch(argument || "");
        }
        if (animated) {
            sheetAnimation.closing = false;
            // popupIn (200 ms), not surface (250): with the window's first frame the open stays
            // under the 300 ms budget (TABLET 4.5 acceptance).
            sheetAnimation.to = 1;
            sheetAnimation.duration = motion.popupIn;
            sheetAnimation.easing.type = Easing.OutCubic;
            sheetAnimation.start();
        }
        syncExpanded();
    }
    function closeSheet() {
        if (!sheetWindow.visible || !sheetWindow.sheet) {
            sheetWindow.visible = false;
            return;
        }
        sheetAnimation.stop();
        sheetAnimation.closing = true;
        sheetAnimation.to = 0;
        sheetAnimation.duration = motion.popupOut;
        sheetAnimation.easing.type = Easing.InCubic;
        sheetAnimation.start();
    }
    NumberAnimation {
        id: sheetAnimation
        property bool closing: false
        target: sheetWindow.sheet
        property: "progress"
        duration: motion.popupIn
        onFinished: {
            if (closing) {
                sheetWindow.visible = false;
            } else if (root.sheetStarted > 0) {
                console.info("launcher: sheet open settled after " + (Date.now() - root.sheetStarted) + " ms, " + root.sheetFrames + " frames");
                root.sheetStarted = 0;
            }
        }
    }
    // The dock's swipe (DOCK-2): the sheet follows the finger, then opens or goes back.
    function beginReveal() {
        openSheet("home", "", false);
    }
    function updateReveal(progress: real) {
        if (sheetWindow.sheet && sheetWindow.visible && !sheetAnimation.running) {
            sheetWindow.sheet.progress = Math.max(0, Math.min(1, progress));
        }
    }
    function endReveal(commit: bool) {
        if (!sheetWindow.sheet) {
            // Not built yet: a committed swipe opens it when it is ready.
            if (!commit) {
                pendingSheet = null;
            } else if (pendingSheet) {
                pendingSheet.animated = true;
            }
            return;
        }
        if (commit) {
            console.info("launcher: sheet opened by the dock swipe");
            sheetAnimation.closing = false;
            sheetAnimation.to = 1;
            sheetAnimation.duration = motion.popupIn;
            sheetAnimation.easing.type = Easing.OutCubic;
            sheetAnimation.start();
        } else {
            closeSheet();
        }
    }

    SheetWindow {
        id: sheetWindow
        launcher: root
        visible: false
        property bool wasActive: false
        onSheetReady: {
            if (root.pendingSheet) {
                const request = root.pendingSheet;
                root.pendingSheet = null;
                root.openSheet(request.mode, request.argument, request.animated);
            }
        }
        onCloseRequested: root.close()
        onFrameSwapped: {
            root.framesDrawn++;
            root.sheetFrames++;
        }
        // Another window took the focus (an app started, the dock, a click on the top bar).
        onActiveChanged: {
            if (active) {
                wasActive = true;
            } else if (visible && wasActive) {
                root.closeSheet();
            }
        }
        onVisibleChanged: {
            if (!visible) {
                wasActive = false;
                root.lastClosed = Date.now();
                root.searchText = "";
                root.syncExpanded();
            }
        }
    }
    // Leaving tablet posture closes the sheet.
    onTabletChanged: {
        if (!tablet && sheetWindow.visible) {
            closeSheet();
        }
    }
    // END tablet sheet

    // `expanded` mirrors the menu state, so that the shell (Meta key, applet shortcut) and other
    // widgets (the dock's Start button) can open and close the menu by toggling it. The shell sets
    // it once by itself when the inline button is first shown; that one is not a request.
    property bool autoExpandPending: false
    property bool syncingExpanded: false

    function syncExpanded() {
        syncingExpanded = true;
        // The windows themselves, not `menuOpen`: inside a visibleChanged handler that binding
        // has not caught up yet, and the state would stay one toggle behind.
        root.expanded = launcherWindow.visible || sheetWindow.visible;
        syncingExpanded = false;
    }

    onExpandedChanged: {
        if (syncingExpanded) {
            return;
        }
        if (autoExpandPending && root.expanded) {
            autoExpandPending = false;
            Qt.callLater(syncExpanded);
            return;
        }
        if (root.expanded && !menuOpen) {
            open("home");
        } else if (!root.expanded && menuOpen) {
            close();
        }
    }

    LauncherWindow {
        id: launcherWindow
        launcher: root
        visible: false
        onVisibleChanged: {
            if (!visible) {
                root.lastClosed = Date.now();
                root.openStarted = 0;
                backdrop.visible = false;
                root.searchText = "";
                root.syncExpanded();
            }
        }
        // The time from the open request to the card's first frame (the budget is 50 ms).
        onFrameSwapped: {
            root.framesDrawn++;
            if (root.openStarted > 0 && visible) {
                console.info("launcher: " + (root.firstShown ? "open" : "first open") + ", first frame after "
                             + (Date.now() - root.openStarted) + " ms");
                root.openStarted = 0;
                root.firstShown = true;
            }
        }
    }

    // Testing: frames drawn by the launcher window since the last "frames" request (openRequest).
    property int framesDrawn: 0
    function reportFrames() {
        const card = launcherWindow.card;
        const sheet = sheetWindow.sheet;
        if (sheetWindow.visible && sheet) {
            console.info("launcher: frames " + framesDrawn + ", sheet open, " + sheet.columns + " x " + sheet.rows + ", pages " + sheet.pageCount
                         + ", grid " + Math.round(sheet.gridWidth) + "x" + Math.round(sheet.gridHeight) + " at y " + Math.round(sheet.gridY)
                         + ", screen " + Math.round(sheet.width) + "x" + Math.round(sheet.height) + ", search focus "
                         + (sheetWindow.activeFocusItem && sheetWindow.activeFocusItem.objectName === "sheetSearch")
                         + ", page " + sheet.currentPage + ", progress " + sheet.progress.toFixed(2));
            framesDrawn = 0;
            return;
        }
        console.info("launcher: frames " + framesDrawn + ", open " + launcherWindow.visible + ", card "
                     + launcherWindow.x + "," + launcherWindow.y + " " + launcherWindow.cardWidth + "x" + launcherWindow.cardHeight
                     + ", pinned rows " + (card ? card.pinnedRows : -1) + ", columns " + (card ? card.columns : -1)
                     + ", screen " + root.screenGeometry.width + "x" + root.screenGeometry.height
                     + ", pinned " + (card && launcherWindow.visible ? card.pinnedCentres(launcherWindow.x, launcherWindow.y) : "-"));
        framesDrawn = 0;
    }

    // A tile dragged out of the card (BACKLOG M3): the launcher closes once the pointer leaves the
    // card, and at the latest when the drag ends.
    property bool dragging: false
    function dragStarted() {
        dragging = true;
    }
    // A drop area of the card lost the drag: unless another one took it in the same event (the
    // pointer only moved between the pinned grid and the rest of the card), it left the card.
    // Qt.callLater, not a Timer: QML timers run on the animation driver, which does not tick
    // during the drag's own event loop.
    property bool dragInCard: false
    function dragLeftCard() {
        dragInCard = false;
        Qt.callLater(checkDragLeft);
    }
    function dragInsideCard() {
        dragInCard = true;
    }
    function checkDragLeft() {
        if (!dragInCard && dragging && launcherWindow.visible) {
            console.info("launcher: drag left the card, closing");
            close();
        }
    }
    function dragEnded() {
        if (dragging) {
            dragging = false;
            console.info("launcher: drag ended");
            close();
        }
    }

    // Search timing: the query's first results (the budget is 100 ms).
    property real searchStarted: 0
    onSearchTextChanged: searchStarted = searchText.length > 0 ? Date.now() : 0
    function noteResults(count: int) {
        if (searchStarted > 0 && count > 0) {
            console.info("launcher: first results for \"" + searchText + "\" after " + (Date.now() - searchStarted) + " ms");
            searchStarted = 0;
        }
    }

    BackdropWindow {
        id: backdrop
        visible: false
        onClicked: root.close()
    }

    // The app-open zoom from the tablet sheet's tiles (TABLET2 M1).
    FusionLaunchZoom {
        id: launchZoom
        dark: {
            const c = Kirigami.Theme.backgroundColor;
            return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
        }
    }
    function playLaunchZoom(item, source, name) {
        launchZoom.play(item, source, name);
    }

    ActionMenu {
        id: actionMenu
        launcher: root
    }

    function openActionMenu(model, index, entry, item, x, y) {
        actionMenu.openFor(model, index, entry, item, x, y);
    }
    // END open and close

    // Relative age text for recent files: "Just now", "12 min ago", "3 hours ago", "Yesterday",
    // "2 days ago", then the date.
    function formatAge(date) {
        const now = new Date();
        const minutes = Math.floor((now.getTime() - date.getTime()) / 60000);
        if (minutes < 1) {
            return i18nc("@info recent file age", "Just now");
        }
        if (minutes < 60) {
            return i18ncp("@info recent file age", "%1 min ago", "%1 min ago", minutes);
        }
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const days = Math.ceil((startOfToday.getTime() - date.getTime()) / 86400000);
        if (date.getTime() >= startOfToday.getTime()) {
            return i18ncp("@info recent file age", "%1 hour ago", "%1 hours ago", Math.floor(minutes / 60));
        }
        if (days <= 1) {
            return i18nc("@info recent file age", "Yesterday");
        }
        if (days < 7) {
            // The board's style: "2 days ago".
            return i18ncp("@info recent file age", "%1 day ago", "%1 days ago", days);
        }
        return date.toLocaleDateString(Qt.locale(), date.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy");
    }

    // Other shell parts can open the launcher in a given state:
    //  - from QML, with the applet item: open("home" | "search" | "apps" | "recent", query) or toggle()
    //  - with desktop scripting, by writing openRequest = "<mode>:<nonce>[:<argument>]", where the
    //    argument is the search text for "search" and the category key (e.g. "graphics") for "category".
    Connections {
        target: Plasmoid.configuration
        function onOpenRequestChanged() {
            const parts = String(Plasmoid.configuration.openRequest || "").split(":");
            const mode = parts[0];
            const argument = parts.slice(2).join(":");
            if (["home", "search", "apps", "recent", "category"].indexOf(mode) >= 0) {
                root.open(mode, argument);
            } else if (mode === "frames") {
                root.reportFrames();
            }
        }
        function onHiddenApplicationsChanged() {
            root.rootModel.refresh();
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action:inmenu", "Edit Applications…")
            icon.name: "kmenuedit"
            visible: Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable
            onTriggered: processRunner.runMenuEditor()
        }
    ]

    Kicker.ProcessRunner {
        id: processRunner
    }

    Component.onCompleted: {
        rootModel.refresh();
    }
}
