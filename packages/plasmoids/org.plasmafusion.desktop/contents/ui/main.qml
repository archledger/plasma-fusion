/*
    SPDX-FileCopyrightText: 2011-2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2011-2019 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014-2015 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami

import org.kde.private.desktopcontainment.folder as Folder

import org.kde.plasma.private.containmentlayoutmanager as ContainmentLayoutManager

import "code/FolderTools.js" as FolderTools

// Plasma Fusion desktop (TABLET2 H1): Plasma 6.7.5's Folder View containment
// (plasma-desktop v6.7.5 containments/desktop/package), unchanged on the laptop. In tablet posture the
// Folder View layer unloads and HomeLayer.qml shows the home screen's app pages over the wallpaper; the
// cards (the containment's applets) stay on page 1 as widgets. Changes against upstream are marked
// "Plasma Fusion".
ContainmentItem {
    id: root

    switchWidth: { switchSize(); }
    switchHeight: { switchSize(); }

    // Only exists because the default CompactRepresentation doesn't:
    // - open on drag
    // - allow defining a custom drop handler
    // TODO remove once it gains that feature (perhaps optionally?)
    compactRepresentation: (isFolder && !isContainment) ? compactRepresentation : null

    objectName: isFolder ? "folder" : "desktop"

    width: isPopup ? undefined : preferredWidth(false) // Initial size when adding to e.g. desktop.
    height: isPopup ? undefined : preferredHeight(false) // Initial size when adding to e.g. desktop.

    function switchSize() {
        // Support expanding into the full representation on very thick vertical panels.
        if (isPopup && Plasmoid.formFactor === PlasmaCore.Types.Vertical) {
            return Kirigami.Units.gridUnit * 8;
        }

        return 0;
    }

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    // Plasma Fusion: the fork is always the Folder View variant (upstream tells the two plugin ids
    // of one package apart by name)
    property bool isFolder: (Plasmoid.pluginName === "org.kde.plasma.folder" || Plasmoid.pluginName === "org.plasmafusion.desktop")
    property bool isContainment: Plasmoid.isContainment
    // Plasma Fusion: file drops go to the Folder View while it is loaded; on the tablet home screen
    // (no Folder View) they go to the widgets on page 1, as on a desktop without folders, and are
    // refused on the app pages.
    readonly property bool folderDrops: isFolder && folderViewLayer.view !== null
    readonly property bool widgetDrops: !tabletHome || appletsLayout.visible

    // Plasma Fusion: the home screen in tablet posture.
    FusionTablet {
        id: tabletState
    }
    Motion {
        id: motion
    }
    FusionMetrics {
        id: fusionMetrics
        area: root.availableScreenRect ?? Qt.rect(0, 0, 1440, 900)
    }
    readonly property bool tabletHome: isContainment && tabletState.tablet
    // The cards' bounding rectangle in the drop area's coordinates (empty without cards).
    property rect cardsRect: Qt.rect(0, 0, 0, 0)
    function updateCardsRect(): void {
        const layout = fullRepresentationItem ? fullRepresentationItem.appletsLayout : null;
        if (!layout) {
            return;
        }
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const child of layout.children) {
            if (!child || child.applet === undefined || child.applet === null || child.width <= 0) {
                continue;
            }
            x0 = Math.min(x0, child.x);
            y0 = Math.min(y0, child.y);
            x1 = Math.max(x1, child.x + child.width);
            y1 = Math.max(y1, child.y + child.height);
        }
        cardsRect = x1 > x0 ? Qt.rect(x0, y0, x1 - x0, y1 - y0) : Qt.rect(0, 0, 0, 0);
    }
    // The home screen's mask follows the cards: look again for a while after the posture changes,
    // a drop (which may add a widget) and any widget added or removed.
    function watchCards(): void {
        Qt.callLater(updateCardsRect);
        cardsTimer.ticks = 0;
        cardsTimer.running = tabletHome;
    }
    onTabletHomeChanged: watchCards()
    Connections {
        target: Plasmoid
        ignoreUnknownSignals: true
        function onAppletAdded() { root.watchCards(); }
        function onAppletRemoved() { root.watchCards(); }
        function onAppletsChanged() { root.watchCards(); }
    }
    Timer {
        id: cardsTimer
        // The cards settle after the layout's own placement: look again for 10 s, then stop (no
        // wake-ups on an idle home screen).
        property int ticks: 0
        interval: 1000
        repeat: true
        onTriggered: {
            root.updateCardsRect();
            if (++ticks >= 10) {
                running = false;
            }
        }
    }
    // The first time a tablet layout is used (per screen size and orientation), the widgets are
    // placed beside page 1's apps: in landscape a column 24 px from the right edge (more columns
    // leftwards when they do not fit), in portrait a row across the top from the grid's 48 px left
    // edge (more rows when they do not fit), 24 px from the top, the dock's 128 px and the page dots
    // kept clear, 16 px between them, each keeping its size. Later moves are the user's (edit
    // mode) and the layout manager saves them under the same key.
    Timer {
        id: arrangeTimer
        // after the layout manager has loaded the new key (it waits 100 ms)
        interval: 600
        onTriggered: root.arrangeTabletCards()
    }
    function arrangeTabletCards(): void {
        const layout = fullRepresentationItem ? fullRepresentationItem.appletsLayout : null;
        if (!tabletHome || !layout || layout.width <= 0 || layout.height <= 0) {
            return;
        }
        const key = layout.configKey;
        const done = Array.from(Plasmoid.configuration.tabletCardsArranged || []).map(String);
        if (done.indexOf(key) >= 0) {
            return;
        }
        const cards = [];
        for (const child of layout.children) {
            if (child && child.applet !== undefined && child.applet !== null && child.width > 0 && child.height > 0) {
                cards.push(child);
            }
        }
        cards.sort((a, b) => a.y !== b.y ? a.y - b.y : a.x - b.x);
        const W = layout.width, H = layout.height, portrait = H > W;
        // (the left edge of page 1's grid in portrait; in landscape 24 px from the right edge, as
        // the desktop's own layout places them, so that page 1 keeps its app columns)
        const side = portrait ? 48 : 24, top = 24, gap = 16, bottom = H - 128 - 36;
        let x = portrait ? side : W - side, y = top, line = 0;
        for (const card of cards) {
            if (portrait) {
                if (x + card.width > W - side && x > side) {
                    x = side;
                    y += line + gap;
                    line = 0;
                }
                layout.releaseSpace(card);
                card.x = x;
                card.y = y;
                x += card.width + gap;
                line = Math.max(line, card.height);
            } else {
                if (y + card.height > bottom && y > top) {
                    x -= line + gap;
                    y = top;
                    line = 0;
                }
                layout.releaseSpace(card);
                card.x = x - card.width;
                card.y = y;
                y += card.height + gap;
                line = Math.max(line, card.width);
            }
        }
        // The containers animate x and y (a Behavior): they reach the new place a moment later, and
        // the layout manager reads their position when it assigns the space.
        arrangeFinish.cards = cards;
        arrangeFinish.key = key;
        arrangeFinish.note = cards.length + (portrait ? " in a row at the top" : " in a column at the right");
        arrangeFinish.restart();
    }
    Timer {
        id: arrangeFinish
        property var cards: []
        property string key: ""
        property string note: ""
        interval: 500
        onTriggered: {
            const layout = root.fullRepresentationItem ? root.fullRepresentationItem.appletsLayout : null;
            if (!layout || layout.configKey !== key) {
                return;
            }
            for (const card of cards) {
                layout.positionItem(card);
            }
            layout.save();
            const done = Array.from(Plasmoid.configuration.tabletCardsArranged || []).map(String);
            Plasmoid.configuration.tabletCardsArranged = done.concat([key]);
            console.info("desktop: tablet widgets arranged for " + key + ": " + note);
            cards = [];
            Qt.callLater(root.updateCardsRect);
        }
    }

    property bool isPopup: (Plasmoid.location !== PlasmaCore.Types.Floating)
    property bool useListViewMode: isPopup && Plasmoid.configuration.viewMode === 0

    property Component appletAppearanceComponent

    property int handleDelay: 800
    property real haloOpacity: 0.5

    readonly property bool isUiReady: Plasmoid.containment.corona.isScreenUiReady(root.screen)
    // Plasma Fusion: the screen's panels came after isUiReady was read (it does not notify).
    // Upstream sets the Folder View loader active at that point, which drops its binding and with
    // it the tablet home screen's "no Folder View"; this keeps the binding.
    property bool screenUiReadyLater: false

    readonly property int hoverActivateDelay: 750 // Magic number that matches Dolphin's auto-expand folders delay.

    readonly property FolderViewLayerLoader folderViewLayer: fullRepresentationItem.folderViewLayer
    readonly property ContainmentLayoutManager.AppletsLayout appletsLayout: fullRepresentationItem.appletsLayout

    // Plasmoid.title is set by a Binding {} in FolderViewLayer
    toolTipSubText: ""
    Plasmoid.icon: (!Plasmoid.configuration.useCustomIcon && folderViewLayer.ready) ? symbolicizeIconName(folderViewLayer.view?.model.iconName) : Plasmoid.configuration.icon

    // We want to do this here rather than in the model because we don't always want
    // symbolic icons everywhere, but we do know that we always want them in this
    // specific representation right here
    function symbolicizeIconName(iconName) {
        const symbolicSuffix = "-symbolic";
        if (iconName?.endsWith(symbolicSuffix)) {
            return iconName;
        }

        return iconName + symbolicSuffix;
    }

    function addLauncher(desktopUrl) {
        if (!folderDrops) {
            return;
        }

        folderViewLayer.view.linkHere(desktopUrl);
    }

    function preferredWidth(forMinimumSize: bool): real {
        if ((isContainment || !folderViewLayer.ready) || (isPopup && !compactRepresentationItem.visible)) {
            return -1;
        } else if (useListViewMode) {
            return (forMinimumSize ? folderViewLayer.view.cellHeight * 4 : Kirigami.Units.gridUnit * 16);
        }

        return (folderViewLayer.view.cellWidth * (forMinimumSize ? 1 : 3)) + (Kirigami.Units.gridUnit * 2);
    }

    function preferredHeight(forMinimumSize: bool): real {
        let height;
        if ((isContainment || !folderViewLayer.ready) || (isPopup && !compactRepresentationItem.visible)) {
            return -1;
        } else if (useListViewMode) {
            height = (folderViewLayer.view.cellHeight * (forMinimumSize ? 1 : 15)) + Kirigami.Units.smallSpacing;
        } else {
            height = (folderViewLayer.view.cellHeight * (forMinimumSize ? 1 : 2)) + Kirigami.Units.gridUnit;
        }

        if (Plasmoid.configuration.labelMode !== 0) {
            height += (folderViewLayer.item as FolderViewLayer).labelHeight;
        }

        return height;
    }

    function isDrag(fromX, fromY, toX, toY) {
        const length = Math.abs(fromX - toX) + Math.abs(fromY - toY);
        return length >= Application.styleHints.startDragDistance;
    }

    onFocusChanged: {
        if (focus && isFolder) {
            (folderViewLayer.item as Item)?.forceActiveFocus();
        }
    }

    onExternalData: (mimetype, data) => {
        Plasmoid.configuration.url = data
    }

    component ShortDropBehavior : Behavior {
        NumberAnimation {
            duration: Kirigami.Units.shortDuration
            easing.type: Easing.InOutQuad
        }
    }

    component LongDropBehavior : Behavior {
        NumberAnimation {
            duration: Kirigami.Units.longDuration
            easing.type: Easing.InOutQuad
        }
    }

    KSvg.FrameSvgItem {
        id: highlightItemSvg

        visible: false

        imagePath: root.isPopup ? "widgets/viewitem" : ""
        prefix: "hover"
    }

    KSvg.FrameSvgItem {
        id: listItemSvg

        visible: false

        imagePath: root.isPopup ? "widgets/viewitem" : ""
        prefix: "normal"
    }

    KSvg.Svg {
        id: toolBoxSvg
        imagePath: "widgets/toolbox"
        property int rightBorder: elementSize("right").width
        property int topBorder: elementSize("top").height
        property int bottomBorder: elementSize("bottom").height
        property int leftBorder: elementSize("left").width
    }

    // FIXME: the use and existence of this property is a workaround
    preloadFullRepresentation: true
    fullRepresentation: FolderViewDropArea {
        id: dropArea

        anchors {
            fill: parent
            leftMargin: (root.isContainment && root.availableScreenRect) ? root.availableScreenRect.x : 0
            topMargin: (root.isContainment && root.availableScreenRect) ? root.availableScreenRect.y : 0

            rightMargin: (root.isContainment && root.availableScreenRect && parent)
                ? (parent.width - root.availableScreenRect.x - root.availableScreenRect.width) : 0

            bottomMargin: (root.isContainment && root.availableScreenRect && parent)
                ? (parent.height - root.availableScreenRect.y - root.availableScreenRect.height) : 0
        }

        LongDropBehavior on anchors.topMargin { }
        LongDropBehavior on anchors.leftMargin { }
        LongDropBehavior on anchors.rightMargin { }
        LongDropBehavior on anchors.bottomMargin { }

        property alias folderViewLayer: folderViewLayer
        property alias appletsLayout: appletsLayout

        // Layout size bindings are set in Component.onCompleted

        preventStealing: true

        onDragEnter: event => {
            if (root.isContainment && Plasmoid.immutable && !(root.folderDrops && FolderTools.isFileDrag(event))) {
                event.ignore();
            }

            // Don't allow any drops while listing.
            if (root.folderDrops && folderViewLayer.view.status === Folder.FolderModel.Listing) {
                event.ignore();
            }

            if (!root.folderDrops && !root.widgetDrops) {
                event.ignore();
            }

            // Firefox tabs are regular drags. Since all of our drop handling is asynchronous
            // we would accept this drop and have Firefox not spawn a new window. (Bug 337711)
            if (event.mimeData.formats.indexOf("application/x-moz-tabbrowser-tab") !== -1) {
                event.ignore();
            }
        }

        onDragMove: event => {
            // TODO: We should reject drag moves onto file items that don't accept drops
            // (cf. QAbstractItemModel::flags() here, but DeclarativeDropArea currently
            // is currently incapable of rejecting drag events.

            // Trigger autoscroll.
            if (root.folderDrops && FolderTools.isFileDrag(event)) {
                handleDragMove(folderViewLayer.view, mapToItem(folderViewLayer.view, event.x, event.y));
            } else if (root.isContainment && root.widgetDrops) {
                appletsLayout.showPlaceHolderAt(
                    Qt.rect(event.x - appletsLayout.minimumItemWidth / 2,
                    event.y - appletsLayout.minimumItemHeight / 2,
                    appletsLayout.minimumItemWidth,
                    appletsLayout.minimumItemHeight)
                );
            }
        }

        onDragLeave: event => {
            // Cancel autoscroll.
            if (root.folderDrops) {
                handleDragEnd(folderViewLayer.view);
            }

            if (root.isContainment) {
                appletsLayout.hidePlaceHolder();
            }
        }

        onDrop: event => {
            if (root.folderDrops && FolderTools.isFileDrag(event)) {
                handleDragEnd(folderViewLayer.view);
                folderViewLayer.view.drop(root, event, mapToItem(folderViewLayer.view, event.x, event.y));
            } else if (root.isContainment && root.widgetDrops) {
                root.processMimeData(event.mimeData,
                    event.x - appletsLayout.placeHolder.width / 2,
                    event.y - appletsLayout.placeHolder.height / 2);
                event.accept(event.proposedAction);
                appletsLayout.hidePlaceHolder();
                root.watchCards();
            }
        }

        Component {
            id: compactRepresentation
            CompactRepresentation { folderView: folderViewLayer.view }
        }

        Connections {
            target: Plasmoid.containment.corona
            ignoreUnknownSignals: true

            function onEditModeChanged() {
                appletsLayout.editMode = Plasmoid.containment.corona.editMode;
            }

            // When adding panels, sizes change. We want to make sure all panels
            // are loaded, and when they all are loaded, we tell the folderViewLayer loader to start.
            function onScreenUiReadyChanged(screen: int, newLayoutReady: bool) {
                if (root.isContainment && root.isFolder && !folderViewLayer.ready && root.screen === screen && newLayoutReady){
                    // We skip x and y since that is handled by the parent of folderViewLayer
                    root.screenUiReadyLater = true;
                }
            }
        }

        ContainmentLayoutManager.AppletsLayout {
            id: appletsLayout
            anchors.fill: parent
            // Plasma Fusion: on the tablet home screen the cards are page 1's widgets (dimmed while
            // the home screen is edited: they are not part of it)
            opacity: !root.tabletHome || !homeLoader.item ? 1
                   : homeLoader.item.currentPage !== 0 ? 0 : homeLoader.item.editing ? 0.25 : 1
            visible: opacity > 0
            Behavior on opacity {
                enabled: motion.animate
                NumberAnimation { duration: motion.toggle }
            }
            relayoutLock: width !== root.availableScreenRect.width || height !== root.availableScreenRect.height
            // NOTE: use root.availableScreenRect and not own width and height as they are updated not atomically
            // Plasma Fusion: the tablet home screen keeps its own widget layout per screen size and
            // orientation, so the laptop desktop's layout (same size in landscape) stays as it was.
            configKey: (root.tabletHome ? "ItemGeometriesTablet-" : "ItemGeometries-")
                       + Math.round(root.screenGeometry.width) + "x" + Math.round(root.screenGeometry.height)
            fallbackConfigKey: (root.tabletHome ? "ItemGeometriesTablet" : "ItemGeometries")
                               + (root.availableScreenRect.width > root.availableScreenRect.height ? "Horizontal" : "Vertical")
            // (the timer does not exist yet when the first key is set, at start-up)
            onConfigKeyChanged: if (arrangeTimer) arrangeTimer.restart()

            Binding on containment {
                value: Plasmoid
                when: Plasmoid.isContainment
            }
            containmentItem: root
            editModeCondition: Plasmoid.immutable
                    ? ContainmentLayoutManager.AppletsLayout.Locked
                    : ContainmentLayoutManager.AppletsLayout.AfterPressAndHold

            // Sets the containment in edit mode when we go in edit mode as well
            onEditModeChanged: Plasmoid.containment.corona.editMode = editMode;

            minimumItemWidth: Kirigami.Units.gridUnit * 3
            minimumItemHeight: minimumItemWidth

            cellWidth: Kirigami.Units.iconSizes.small
            cellHeight: cellWidth
            defaultItemWidth: cellWidth * 6
            defaultItemHeight: cellHeight * 6

            eventManagerToFilter: (folderViewLayer.item as FolderViewLayer)?.view.view ?? null

            appletContainerComponent: ContainmentLayoutManager.BasicAppletContainer {
                id: appletContainer

                editModeCondition: Plasmoid.immutable
                    ? ContainmentLayoutManager.ItemContainer.Locked
                    : ContainmentLayoutManager.ItemContainer.AfterPressAndHold

                configOverlaySource: "ConfigOverlay.qml"

                Connections {
                    target: appletsLayout
                    function onEditModeChanged(): void {
                        if (!Plasmoid.containment.corona.editMode) {
                            appletContainer.cancelEdit();
                        }
                    }
                }

                onAppletChanged: {
                    applet.visible = true
                }

                Drag.dragType: Drag.Automatic
                Drag.active: false
                Drag.supportedActions: Qt.MoveAction
                Drag.mimeData: {
                    "text/x-plasmoidinstanceid": Plasmoid.containment.id+':'+appletContainer.applet.plasmoid.id
                }
                Drag.onDragFinished: dropEvent => {
                    if (dropEvent == Qt.MoveAction) {
                        appletContainer.visible = true
                        appletContainer.applet.visible = true
                        //currentApplet.applet.plasmoid.internalAction("remove").trigger()
                    } else {
                        appletContainer.visible = true
                        //appletsModel.insert(configurationArea.draggedItemIndex - 1, {applet: appletContainer.applet});
                    }
                    //appletContainer.destroy()
                    //root.dragAndDropping = false
                    //root.layoutManager.save()
                }

                onUserDrag: (newPosition, dragCenter) => {
                    const pos = mapToItem(root.parent, dragCenter.x, dragCenter.y);
                    const newCont = root.containmentItemAt(pos.x, pos.y);
                    // User likely touched screen edges, so ignore that.
                    if (!newCont) {
                        return;
                    }

                    if (newCont.plasmoid !== Plasmoid) {
                        // First go out of applet edit mode, get rid of the config overlay, release mouse grabs in preparation of applet reparenting
                        cancelEdit();
                        appletsLayout.hidePlaceHolder();
                        appletContainer.grabToImage(result => {
                            appletContainer.Drag.imageSource = result.url
                            appletContainer.visible = false
                            appletContainer.Drag.active = true
                        })
                    }
                }

                ShortDropBehavior on x { }
                ShortDropBehavior on y { }
            }

            placeHolder: ContainmentLayoutManager.PlaceHolder {}

            component FolderViewLayerLoader: Loader {
                property bool ready: status === Loader.Ready
                property FolderView view: (item as FolderViewLayer)?.view ?? null
                property Folder.FolderModel model: (item as FolderViewLayer)?.model ?? null

                source: "FolderViewLayer.qml"
            }


            FolderViewLayerLoader {
                id: folderViewLayer

                anchors.fill: parent

                focus: true

                // Do not set this active by default for desktop, and disable it when folderMode is not used
                active: {
                    if (root.tabletHome) {
                        // Plasma Fusion: no Folder View on the tablet home screen
                        return false;
                    }
                    if (root.isFolder){
                        if (!root.isContainment) {
                            // We are a folder widget
                            return true;
                        } else {
                            // For desktop, test if the screen is ready
                            return root.isUiReady || root.screenUiReadyLater;
                        }
                    }
                    return false;
                }
                asynchronous: false
                onActiveChanged: if (root.isContainment) console.info("desktop: folder view " + (active ? "loaded" : "unloaded")
                                                                      + (root.tabletHome ? " (tablet)" : ""))

                onFocusChanged: {
                    if (!focus && model) {
                        model.clearSelection();
                    }
                }

                Binding {
                    target: folderViewLayer.item
                    property: "isPopup"
                    value: root.isPopup
                }

                Binding {
                    target: folderViewLayer.item
                    property: "useListViewMode"
                    value: root.useListViewMode
                }

                Connections {
                    target: folderViewLayer.view

                    // `FolderViewDropArea` is not a FocusScope. We need to forward manually.
                    function onPressed() {
                        folderViewLayer.forceActiveFocus();
                    }
                }
            }
        }

        // Plasma Fusion: the home screen's app pages (tablet posture), over the cards' layout so
        // its swipes and taps work; presses on page 1's widgets pass through to the cards.
        Loader {
            id: homeLoader
            anchors.fill: parent
            active: root.tabletHome
            sourceComponent: HomeLayer {
                plasmoidItem: root
                metrics: fusionMetrics
                motion: motion
                widgetRect: root.cardsRect
                containmentMask: QtObject {
                    function contains(point: point): bool {
                        const r = root.cardsRect;
                        const onPage1 = homeLoader.item ? homeLoader.item.currentPage === 0 : true;
                        if (homeLoader.item && homeLoader.item.editing) {
                            return true;
                        }
                        return !(onPage1 && r.width > 0 && point.x >= r.x && point.x < r.x + r.width
                                 && point.y >= r.y && point.y < r.y + r.height);
                    }
                }
            }
        }

        PlasmaCore.Action {
            id: configAction
            text: i18nc("@action:inmenu opens config dialog", "Desktop and Wallpaper")
            icon.name: "preferences-desktop-wallpaper"
            shortcut:"Ctrl+Shift+D"
            onTriggered: Plasmoid.containment.configureRequested(Plasmoid)
        }

        Component.onCompleted: {
            // Layout bindings need to be set delayed; the intermediate steps as the other bindings happen cause loops
            Qt.callLater( () => {
                dropArea.Layout.minimumWidth = Qt.binding(() => root.preferredWidth(root.isPopup))
                dropArea.Layout.minimumHeight = Qt.binding(() => root.preferredHeight(root.isPopup))

                dropArea.Layout.preferredWidth = Qt.binding(() => root.preferredWidth(false))
                dropArea.Layout.preferredHeight = Qt.binding(() => root.preferredHeight(false))

                // Maximum size is intentionally unbounded
            })

            if (!Plasmoid.isContainment) {
                return;
            }

            Plasmoid.setInternalAction("configure", configAction)
        }
    }
}
