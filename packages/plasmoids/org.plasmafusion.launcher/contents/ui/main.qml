/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.private.kicker as Kicker

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
    readonly property bool menuOpen: launcherWindow.visible
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
        const installed = {};
        for (let i = 0; i < installedReader.count; ++i) {
            const entry = installedReader.objectAt(i);
            if (entry && entry.favoriteId) {
                installed[entry.favoriteId] = true;
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
        const current = [];
        for (let i = 0; i < pinnedReader.count; ++i) {
            const entry = pinnedReader.objectAt(i);
            current.push(entry ? String(entry.favoriteId) : "");
        }
        const ids = [];
        const duplicates = [];
        for (const slot of Launcher.pinnedSlots(Plasmoid.configuration.favorites)) {
            const pick = slot.find(id => id.indexOf("preferred://") === 0 || installed[id] || current.indexOf(id) >= 0);
            if (pick) {
                ids.push(pick);
                // Another app for the same slot would show a second tile for the same role
                // (Fedora pins Kontact next to KMail, GNOME Files next to Dolphin).
                duplicates.push(...slot.filter(id => id !== pick && current.indexOf(id) >= 0));
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
    function placeWindows() {
        const s = screenArea();
        const m = launcherWindow.metrics;
        const bottom = Math.min(s.y + s.height - Plasmoid.configuration.bottomOffset, s.availBottom - 4);
        const top = s.availTop + 8;
        const height = Math.max(m.px(420), Math.min(m.px(700), bottom - top));
        launcherWindow.cardWidth = m.windowSize(Math.min(m.px(680), s.width - 32));
        launcherWindow.cardHeight = m.windowSize(height);
        launcherWindow.x = Math.round(s.x + (s.width - launcherWindow.cardWidth) / 2);
        launcherWindow.y = Math.round(Math.max(top, bottom - height));
        // The dim layer covers the whole screen; panels stay above it (they are in a higher layer).
        backdrop.area = Qt.rect(s.x, s.y, s.width, s.height);
    }

    function open(mode, argument) {
        placeWindows();
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
        launcherWindow.visible = false;
    }

    function toggle() {
        if (launcherWindow.visible) {
            close();
        } else {
            open("home");
        }
    }

    // True while the menu is open or was closed a moment ago (a click on the panel button can
    // deactivate and close the menu before the click itself arrives).
    function recentlyOpen() {
        return launcherWindow.visible || (Date.now() - lastClosed) < 300;
    }

    // `expanded` mirrors the menu state, so that the shell (Meta key, applet shortcut) and other
    // widgets (the dock's Start button) can open and close the menu by toggling it. The shell sets
    // it once by itself when the inline button is first shown; that one is not a request.
    property bool autoExpandPending: false
    property bool syncingExpanded: false

    function syncExpanded() {
        syncingExpanded = true;
        root.expanded = launcherWindow.visible;
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
        if (root.expanded && !launcherWindow.visible) {
            open("home");
        } else if (!root.expanded && launcherWindow.visible) {
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
                backdrop.visible = false;
                root.searchText = "";
                root.syncExpanded();
            }
        }
    }

    BackdropWindow {
        id: backdrop
        visible: false
        onClicked: root.close()
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
