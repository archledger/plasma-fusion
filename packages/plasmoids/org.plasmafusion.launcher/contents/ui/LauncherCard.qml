/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.extras as PlasmaExtras

import "../code/launcher.js" as Launcher

// The launcher card in board coordinates: (0, 0) is the top-left corner of the 680 px wide
// window, including the Plasma style frame (1 px edge + 24 px padding = 25 px inset).
FocusScope {
    id: card

    property var launcher
    property FusionColors pal
    property string fontFamily
    property real cornerRadius: 22

    readonly property int inset: 25
    readonly property int innerWidth: width - 2 * inset

    // home | category | apps | recent
    property string view: "home"
    property int chipIndex: 0
    readonly property bool searching: search.text.length > 0
    // Enter was pressed before the first search results arrived: launch the top one when they do.
    property bool launchWhenReady: false
    readonly property var chips: launcher ? launcher.chips : []
    readonly property var categoryModel: launcher && view === "category" && chipIndex > 0 && chipIndex < chips.length
        ? launcher.rootModel.modelForRow(chips[chipIndex].row) : null
    readonly property var allAppsModel: launcher && view === "apps" ? launcher.allAppsModel() : null

    // Vertical budget of the home view (board: 3 pinned rows and 2 recent rows in a 700 px card).
    readonly property real bodyHeight: body.height
    readonly property bool recommendedFits: launcher && launcher.showRecommended && bodyHeight >= 88 + 2 * 88 + 168
    readonly property int pinnedRows: Math.max(1, Math.min(3, Math.floor((bodyHeight - 88 - (recommendedFits ? 168 : 0) + 4) / 88)))

    function reset() {
        search.clear();
        launchWhenReady = false;
        view = "home";
        chipIndex = 0;
        for (const g of [pinnedGrid, docGrid, mainGrid, recentGrid]) {
            g.currentIndex = -1;
            g.keyboardNavigation = false;
            g.resetPointer();
            g.positionViewAtBeginning();
        }
        results.keyboardNavigation = false;
        results.resetPointer();
        search.input.forceActiveFocus(Qt.OtherFocusReason);
    }

    function openMode(mode: string, argument: string) {
        reset();
        if (mode === "apps" || mode === "recent") {
            view = mode;
        } else if (mode === "category") {
            const index = chips.findIndex(c => c.key === argument);
            if (index > 0) {
                selectChip(index);
            }
        } else if (mode === "search" && argument.length > 0) {
            search.text = argument;
            search.input.cursorPosition = argument.length;
        }
    }

    function selectChip(index: int) {
        if (index < 0 || index >= chips.length) {
            return;
        }
        chipIndex = index;
        view = index === 0 ? "home" : "category";
        mainGrid.currentIndex = -1;
        mainGrid.positionViewAtBeginning();
    }

    function openMoreCategories() {
        moreMenu.openRelative();
    }

    function goHome() {
        selectChip(0);
    }

    // Text typed while a list or grid has focus goes to the search field; "\b" is Backspace.
    function typeIntoSearch(text: string) {
        search.input.forceActiveFocus(Qt.OtherFocusReason);
        if (text === "\b") {
            const at = search.input.cursorPosition;
            if (search.input.selectedText.length > 0) {
                search.input.remove(search.input.selectionStart, search.input.selectionEnd);
            } else if (at > 0) {
                search.input.remove(at - 1, at);
            }
            return;
        }
        search.input.insert(search.input.cursorPosition, text);
    }

    // The first grid below the chips in the current view.
    function primaryGrid() {
        if (view === "home") {
            return pinnedGrid;
        }
        if (view === "recent") {
            return recentGrid;
        }
        return mainGrid;
    }

    function focusSearch() {
        search.input.forceActiveFocus(Qt.BacktabFocusReason);
    }

    function focusFooter() {
        footer.firstButton.forceActiveFocus(Qt.TabFocusReason);
    }

    Keys.onEscapePressed: handleEscape()

    function handleEscape() {
        if (searching) {
            search.clear();
            search.input.forceActiveFocus(Qt.OtherFocusReason);
        } else if (view !== "home") {
            goHome();
            search.input.forceActiveFocus(Qt.OtherFocusReason);
        } else if (launcher) {
            launcher.close();
        }
    }

    SearchBox {
        id: search
        x: card.inset
        y: card.inset
        width: card.innerWidth
        height: 50
        focus: true
        pal: card.pal
        fontFamily: card.fontFamily

        onTextChanged: {
            card.launchWhenReady = false;
            // New results under a resting pointer must not look hovered.
            results.resetPointer();
            if (card.launcher) {
                card.launcher.searchText = text;
            }
        }
        onNavigateDown: {
            if (card.searching) {
                if (results.count > 0) {
                    results.keyboardNavigation = true;
                    results.pointerActive = false;
                    results.currentIndex = Math.min(1, results.count - 1);
                    results.forceActiveFocus(Qt.TabFocusReason);
                }
            } else {
                card.primaryGrid().focusFirst();
            }
        }
        onAccepted: {
            if (card.searching) {
                if (results.count > 0) {
                    results.launch(Math.max(0, results.currentIndex));
                } else {
                    card.launchWhenReady = true;
                }
            }
            // With an empty field Enter does nothing: the grids launch with Enter themselves
            // once the keyboard is in them, and a hovered tile is not a choice.
        }
        onEscapePressed: card.handleEscape()
        onNavigateTab: backwards => {
            if (backwards) {
                card.focusFooterLast();
            } else if (card.searching) {
                results.forceActiveFocus(Qt.TabFocusReason);
            } else {
                chipRow.forceActiveFocus(Qt.TabFocusReason);
            }
        }
    }

    function focusFooterLast() {
        footer.lastButton.forceActiveFocus(Qt.BacktabFocusReason);
    }

    Item {
        id: body
        x: card.inset
        y: search.y + search.height + 16
        width: card.innerWidth
        height: footer.y - 16 - y

        // Category chips. Chips that do not fit move into a round "more" chip with a menu.
        FocusScope {
            id: chipRow
            width: parent.width
            height: 30
            visible: !card.searching
            activeFocusOnTab: true
            Accessible.role: Accessible.PageTabList
            Accessible.name: i18nc("@label", "Categories")

            readonly property int fitCount: {
                const n = chipRepeater.count;
                let total = 0;
                for (let i = 0; i < n; ++i) {
                    const item = chipRepeater.itemAt(i);
                    total += (item ? item.implicitWidth : 0) + (i > 0 ? 8 : 0);
                }
                if (total <= width) {
                    return n;
                }
                let used = 0;
                let k = 0;
                for (let i = 0; i < n; ++i) {
                    const item = chipRepeater.itemAt(i);
                    const w = (item ? item.implicitWidth : 0) + (i > 0 ? 8 : 0);
                    if (used + w + 38 > width) {
                        break;
                    }
                    used += w;
                    k++;
                }
                return Math.max(1, k);
            }
            readonly property bool overflowing: fitCount < chipRepeater.count

            Row {
                spacing: 8

                Repeater {
                    id: chipRepeater
                    model: card.chips

                    delegate: Chip {
                        required property int index
                        required property var modelData
                        visible: index < chipRow.fitCount
                        pal: card.pal
                        fontFamily: card.fontFamily
                        text: modelData.label
                        selected: index === card.chipIndex
                        showFocus: selected && chipRow.activeFocus
                        onClicked: card.selectChip(index)
                    }
                }

                Chip {
                    id: moreChip
                    visible: chipRow.overflowing
                    implicitWidth: 30
                    pal: card.pal
                    fontFamily: card.fontFamily
                    text: ""
                    selected: card.chipIndex >= chipRow.fitCount
                    showFocus: selected && chipRow.activeFocus
                    Accessible.name: i18nc("@action:button", "More categories")
                    onClicked: card.openMoreCategories()

                    Glyph {
                        anchors.centerIn: parent
                        name: "more"
                        size: 16
                        strokeWidth: 3.8
                        color: moreChip.selected ? "#ffffff" : card.pal.textSecondary
                    }
                }
            }

            Keys.onLeftPressed: card.selectChip(Math.max(0, card.chipIndex - 1))
            Keys.onRightPressed: card.selectChip(Math.min(card.chips.length - 1, card.chipIndex + 1))
            Keys.onUpPressed: card.focusSearch()
            Keys.onDownPressed: card.primaryGrid().focusFirst()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (card.chipIndex >= chipRow.fitCount) {
                        card.openMoreCategories();
                    } else {
                        card.primaryGrid().focusFirst();
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backspace) {
                    card.typeIntoSearch("\b");
                    event.accepted = true;
                } else if (Launcher.isPrintable(event.text) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                    card.typeIntoSearch(event.text);
                    event.accepted = true;
                }
            }
            Keys.onTabPressed: {
                if (card.view === "category") {
                    mainGrid.focusFirst();
                } else {
                    topHeader.button.forceActiveFocus(Qt.TabFocusReason);
                }
            }
            Keys.onBacktabPressed: card.focusSearch()
        }

        PlasmaExtras.Menu {
            id: moreMenu
            visualParent: moreChip
            placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
        }

        Instantiator {
            model: chipRow.overflowing ? card.chips.slice(chipRow.fitCount) : []
            delegate: PlasmaExtras.MenuItem {
                required property int index
                required property var modelData
                text: modelData.label
                // One choice: mark the current category instead of showing checkboxes.
                icon: card.chipIndex === chipRow.fitCount + index ? "checkmark" : ""
                onClicked: card.selectChip(chipRow.fitCount + index)
            }
            onObjectAdded: (index, object) => moreMenu.addMenuItem(object)
            onObjectRemoved: (index, object) => moreMenu.removeMenuItem(object)
        }

        // "Pinned" / "All apps" / "Recommended" header of the view.
        SectionHeader {
            id: topHeader
            y: 46
            width: parent.width
            visible: !card.searching
            pal: card.pal
            fontFamily: card.fontFamily
            title: card.view === "category" && card.chipIndex < card.chips.length ? card.chips[card.chipIndex].label
                 : card.view === "apps" ? i18nc("@title", "All apps")
                 : card.view === "recent" ? i18nc("@title", "Recommended")
                 : i18nc("@title", "Pinned")
            buttonText: card.view === "home" ? i18nc("@action:button", "All apps")
                      : card.view === "category" ? "" : i18nc("@action:button", "Back")
            buttonBack: card.view !== "home"
            onButtonClicked: {
                if (card.view === "home") {
                    card.view = "apps";
                    mainGrid.currentIndex = -1;
                    mainGrid.positionViewAtBeginning();
                } else {
                    card.goHome();
                }
            }
            onNavTab: card.primaryGrid().focusFirst()
            onNavBacktab: chipRow.forceActiveFocus(Qt.BacktabFocusReason)
            onNavDown: card.primaryGrid().focusFirst()
            onNavUp: chipRow.forceActiveFocus(Qt.BacktabFocusReason)
        }

        // Home: pinned apps (6 columns, up to 3 rows).
        AppGrid {
            id: pinnedGrid
            y: 88
            width: parent.width + gap
            height: card.pinnedRows * cellHeight
            visible: !card.searching && card.view === "home"
            interactive: count > card.pinnedRows * columns
            pal: card.pal
            fontFamily: card.fontFamily
            launcher: card.launcher
            designLabels: card.launcher ? card.launcher.designLabels : false
            model: card.launcher ? card.launcher.favoritesModel : null
            onExitTop: chipRow.forceActiveFocus(Qt.BacktabFocusReason)
            onExitBottom: {
                if (docGrid.visible && docGrid.count > 0) {
                    docGrid.focusFirst();
                } else {
                    card.focusFooter();
                }
            }
            onTyped: text => card.typeIntoSearch(text)
            Keys.onTabPressed: {
                if (recHeader.visible) {
                    recHeader.button.forceActiveFocus(Qt.TabFocusReason);
                } else {
                    card.focusFooter();
                }
            }
            Keys.onBacktabPressed: topHeader.button.forceActiveFocus(Qt.BacktabFocusReason)

            FusionText {
                anchors.centerIn: parent
                width: parent.width - 40
                visible: parent.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: i18nc("@info", "Pin apps here with right-click → Pin to Launcher")
                color: card.pal.muted
                family: card.fontFamily
                px: 13
            }
        }

        SectionHeader {
            id: recHeader
            y: pinnedGrid.y + pinnedGrid.height - pinnedGrid.gap + 16
            width: parent.width
            visible: !card.searching && card.view === "home" && card.recommendedFits
            pal: card.pal
            fontFamily: card.fontFamily
            title: i18nc("@title", "Recommended")
            buttonText: i18nc("@action:button", "More")
            onButtonClicked: {
                card.view = "recent";
                recentGrid.currentIndex = -1;
                recentGrid.positionViewAtBeginning();
            }
            onNavTab: {
                if (docGrid.count > 0) {
                    docGrid.focusFirst();
                } else {
                    card.focusFooter();
                }
            }
            onNavDown: navTab()
            onNavBacktab: pinnedGrid.focusFirst()
            onNavUp: pinnedGrid.focusFirst()
        }

        // Home: four most recent files.
        DocGrid {
            id: docGrid
            y: recHeader.y + 26 + 16
            width: parent.width + gap
            height: 2 * cellHeight
            visible: recHeader.visible
            interactive: false
            limit: 4
            pal: card.pal
            fontFamily: card.fontFamily
            launcher: card.launcher
            model: card.launcher ? card.launcher.recentDocsModel : null
            onExitTop: {
                pinnedGrid.keyboardNavigation = true;
                pinnedGrid.currentIndex = Math.max(0, pinnedGrid.count - 1);
                pinnedGrid.forceActiveFocus(Qt.BacktabFocusReason);
            }
            onExitBottom: card.focusFooter()
            onTyped: text => card.typeIntoSearch(text)
            Keys.onTabPressed: card.focusFooter()
            Keys.onBacktabPressed: recHeader.button.forceActiveFocus(Qt.BacktabFocusReason)

            FusionText {
                anchors.fill: parent
                anchors.rightMargin: parent.gap
                visible: parent.count === 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                text: i18nc("@info", "Files you open will show up here")
                color: card.pal.muted
                family: card.fontFamily
                px: 13
            }
        }

        // Category and "All apps" views.
        AppGrid {
            id: mainGrid
            y: 88
            width: parent.width + gap
            height: parent.height - y
            visible: !card.searching && (card.view === "category" || card.view === "apps")
            pal: card.pal
            fontFamily: card.fontFamily
            launcher: card.launcher
            model: card.view === "category" ? card.categoryModel : card.allAppsModel
            onExitTop: {
                if (card.view === "apps") {
                    topHeader.button.forceActiveFocus(Qt.BacktabFocusReason);
                } else {
                    chipRow.forceActiveFocus(Qt.BacktabFocusReason);
                }
            }
            onExitBottom: card.focusFooter()
            onTyped: text => card.typeIntoSearch(text)
            Keys.onTabPressed: card.focusFooter()
            Keys.onBacktabPressed: {
                if (card.view === "apps") {
                    topHeader.button.forceActiveFocus(Qt.BacktabFocusReason);
                } else {
                    chipRow.forceActiveFocus(Qt.BacktabFocusReason);
                }
            }
        }

        // "More": every recent file.
        DocGrid {
            id: recentGrid
            y: 88
            width: parent.width + gap
            height: parent.height - y
            visible: !card.searching && card.view === "recent"
            pal: card.pal
            fontFamily: card.fontFamily
            launcher: card.launcher
            model: visible && card.launcher ? card.launcher.recentDocsModel : null
            onExitTop: topHeader.button.forceActiveFocus(Qt.BacktabFocusReason)
            onExitBottom: card.focusFooter()
            onTyped: text => card.typeIntoSearch(text)
            Keys.onTabPressed: card.focusFooter()
            Keys.onBacktabPressed: topHeader.button.forceActiveFocus(Qt.BacktabFocusReason)
        }

        // Search results.
        ResultsList {
            id: results
            width: parent.width + 10
            height: parent.height
            visible: card.searching
            pal: card.pal
            fontFamily: card.fontFamily
            launcher: card.launcher
            model: card.launcher && card.launcher.runnerModel.count > 0 ? card.launcher.runnerModel.modelForRow(0) : null
            onCountChanged: {
                if (!activeFocus) {
                    currentIndex = count > 0 ? 0 : -1;
                }
                if (card.launchWhenReady && count > 0) {
                    card.launchWhenReady = false;
                    launch(0);
                }
            }
            onExitTop: card.focusSearch()
            onTyped: text => card.typeIntoSearch(text)
            Keys.onTabPressed: card.focusFooter()
            Keys.onBacktabPressed: card.focusSearch()

            FusionText {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 40
                width: parent.width - 60
                visible: card.searching && parent.count === 0 && card.launcher && !card.launcher.runnerModel.querying
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: i18nc("@info", "No results for “%1”", search.text)
                color: card.pal.muted
                family: card.fontFamily
                px: 13
            }
        }
    }

    Footer {
        id: footer
        x: 1
        width: card.width - 2
        height: 62
        y: card.height - 1 - height
        pal: card.pal
        fontFamily: card.fontFamily
        launcher: card.launcher
        cornerRadius: Math.max(0, card.cornerRadius - 1)
        onExitTop: {
            const grid = card.searching ? results : (card.view === "home" && docGrid.visible && docGrid.count > 0 ? docGrid : card.primaryGrid());
            if (grid === results) {
                results.forceActiveFocus(Qt.BacktabFocusReason);
            } else {
                grid.focusFirst();
            }
        }
        onBacktabFromFirst: {
            if (card.searching) {
                results.forceActiveFocus(Qt.BacktabFocusReason);
            } else if (card.view === "home" && docGrid.visible && docGrid.count > 0) {
                docGrid.focusFirst();
            } else {
                card.primaryGrid().focusFirst();
            }
        }
        onTabFromLast: card.focusSearch()
    }
}
