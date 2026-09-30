/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support

import "../code/weather.js" as Weather

// Location search of the weather card: asks every weather provider of the Plasma5Support
// weather engine ("<ion>|validate|<text>") and lists the places they know. The stock weather
// widget's own location page is compiled into its plugin and cannot be reused.
KCM.ScrollViewKCM {
    id: page

    property string cfg_source
    property string cfg_placeDisplayName
    property string cfg_providerName
    property string cfg_sourceDefault
    property string cfg_placeDisplayNameDefault
    property string cfg_providerNameDefault
    // Keys of the other page (the settings dialog hands every key to every page).
    property int cfg_updateInterval
    property int cfg_updateIntervalDefault
    property int cfg_temperatureUnit
    property int cfg_temperatureUnitDefault
    property int cfg_titleMode
    property int cfg_titleModeDefault

    property string query: ""
    readonly property string regionalIon: Weather.regionalIon(Qt.locale().name)
    property var pendingSources: []
    property bool searching: false

    readonly property var providers: Weather.parseIons(engine.data["ions"])
    // A search typed before the provider list arrived runs again once it is there.
    onProvidersChanged: {
        if (query !== "" && pendingSources.length === 0 && results.count === 0) {
            search(query);
        }
    }

    function providerName(ion: string): string {
        for (const p of providers) {
            if (p.ion === ion) {
                return p.name;
            }
        }
        return ion;
    }

    function stopSearch(): void {
        for (const s of pendingSources) {
            engine.disconnectSource(s);
        }
        pendingSources = [];
        searching = false;
    }

    function search(text: string): void {
        const t = Weather.searchText(text);
        stopSearch();
        results.clear();
        query = t;
        if (t.length < 2) {
            return;
        }
        const sources = [];
        for (const p of providers) {
            sources.push(p.ion + "|validate|" + t);
        }
        pendingSources = sources;
        searching = sources.length > 0;
        for (const s of sources) {
            engine.connectSource(s);
        }
        searchTimeout.restart();
    }

    function addResults(source: string, data: var): void {
        if (pendingSources.indexOf(source) === -1 || !data || typeof data.validate !== "string") {
            return;
        }
        const found = Weather.parseValidate(data.validate);
        for (const e of found) {
            let known = false;
            for (let i = 0; i < results.count; ++i) {
                if (results.get(i).source === e.source) {
                    known = true;
                    break;
                }
            }
            if (!known) {
                // Places named exactly as searched first, then names starting with it; within
                // each group the region's own weather service first ("London" in en_GB: the BBC's
                // London before NOAA's London, Kentucky), then the order the providers answered.
                const rank = relevance(e.place) * 2 + (e.ion === page.regionalIon ? 0 : 1);
                let at = results.count;
                for (let i = 0; i < results.count; ++i) {
                    if (results.get(i).rank > rank) {
                        at = i;
                        break;
                    }
                }
                results.insert(at, { "source": e.source, "place": e.place, "provider": providerName(e.ion), "rank": rank });
            }
        }
        // One reply per provider; the search is over when every provider answered.
        const left = pendingSources.filter(s => s !== source && !(engine.data[s] && engine.data[s].validate));
        if (left.length === 0) {
            searching = false;
        }
    }

    function relevance(place: string): int {
        const name = Weather.shortPlace(place).toLocaleLowerCase();
        const q = query.toLocaleLowerCase();
        return name === q ? 0 : name.startsWith(q) ? 1 : 2;
    }

    // An empty source forgets the location (Clear).
    function select(source: string, place: string, provider: string): void {
        if (source !== "" && !Weather.isSafeSource(source)) {
            return;
        }
        cfg_source = source;
        cfg_placeDisplayName = place;
        cfg_providerName = provider;
    }

    P5Support.DataSource {
        id: engine
        engine: "weather"
        // Direct delivery: every provider answers a validate source once.
        interval: 0
        connectedSources: ["ions"]
        onNewData: (source, data) => {
            if (source.indexOf("|validate|") !== -1) {
                page.addResults(source, data);
            }
        }
    }

    Timer {
        id: searchTimeout
        interval: 20000
        onTriggered: page.searching = false
    }
    Timer {
        id: typingDelay
        interval: 900
        onTriggered: page.search(searchField.text)
    }

    Component.onDestruction: stopSearch()
    // Typing can start right away when the page opens.
    Component.onCompleted: Qt.callLater(() => searchField.forceActiveFocus())

    header: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.FormLayout {
            Layout.fillWidth: true
            RowLayout {
                Kirigami.FormData.label: i18nc("@label", "Location:")
                spacing: Kirigami.Units.smallSpacing
                QQC2.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: page.cfg_source === ""
                          ? i18nc("@info no weather location chosen", "None")
                          : i18nc("@info place (weather provider)", "%1 (%2)",
                                  page.cfg_placeDisplayName || page.cfg_source.split("|")[2],
                                  page.providerName(page.cfg_source.split("|")[0]))
                }
                QQC2.Button {
                    visible: page.cfg_source !== ""
                    icon.name: "edit-clear"
                    text: i18nc("@action:button forget the weather location", "Clear")
                    onClicked: page.select("", "", "")
                }
            }
        }

        Kirigami.SearchField {
            id: searchField
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            placeholderText: i18nc("@info:placeholder", "Search for a city…")
            focus: true
            autoAccept: false
            onTextChanged: typingDelay.restart()
            // Enter searches now. The key is taken here: a text field passes Return on, and the
            // settings dialog closes on any Return that reaches it (AppletConfiguration.qml).
            function searchNow(event: KeyEvent): void {
                event.accepted = true;
                typingDelay.stop();
                page.search(text);
            }
            Keys.onReturnPressed: event => searchNow(event)
            Keys.onEnterPressed: event => searchNow(event)
            // Down goes to the first result (or the chosen one), ready for Enter.
            Keys.onDownPressed: {
                if (results.count === 0) {
                    return;
                }
                if (placesView.currentIndex < 0) {
                    placesView.currentIndex = 0;
                }
                placesView.forceActiveFocus(Qt.TabFocusReason);
            }
        }
    }

    view: ListView {
        id: placesView
        model: ListModel {
            id: results
        }
        activeFocusOnTab: true
        keyNavigationEnabled: true
        currentIndex: -1
        // Keyboard cursor: a focus frame over the current place while the list has the keyboard.
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 0
        highlight: Rectangle {
            z: 3
            visible: placesView.activeFocus
            color: "transparent"
            radius: Kirigami.Units.cornerRadius
            border.width: 2
            border.color: Kirigami.Theme.focusColor
        }
        onActiveFocusChanged: {
            if (activeFocus && currentIndex < 0 && count > 0) {
                currentIndex = 0;
            }
        }

        // Enter picks the current place; Enter on the place already picked is left to the
        // dialog (OK), so Down, Enter, Enter chooses the first result and closes the settings.
        function pick(event: KeyEvent): void {
            if (currentIndex < 0 || currentIndex >= results.count) {
                event.accepted = false;
                return;
            }
            const e = results.get(currentIndex);
            if (e.source === page.cfg_source) {
                event.accepted = false;
                return;
            }
            page.select(e.source, e.place, e.provider);
            event.accepted = true;
        }
        Keys.onReturnPressed: event => pick(event)
        Keys.onEnterPressed: event => pick(event)
        Keys.onSpacePressed: event => pick(event)
        // Up from the first result goes back to the search field.
        Keys.onUpPressed: event => {
            if (currentIndex <= 0) {
                searchField.forceActiveFocus(Qt.BacktabFocusReason);
            } else {
                decrementCurrentIndex();
            }
        }

        delegate: QQC2.ItemDelegate {
            id: item
            required property int index
            required property string source
            required property string place
            required property string provider

            width: ListView.view.width
            highlighted: source === page.cfg_source
            Accessible.name: i18nc("@info place (weather provider)", "%1 (%2)", place, provider)
            onClicked: {
                ListView.view.currentIndex = index;
                page.select(source, place, provider);
            }

            contentItem: ColumnLayout {
                spacing: 0
                QQC2.Label {
                    Layout.fillWidth: true
                    text: item.place
                    elide: Text.ElideRight
                    color: item.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: item.provider
                    elide: Text.ElideRight
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    color: item.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                }
            }
        }

        QQC2.BusyIndicator {
            anchors.centerIn: parent
            visible: page.searching && results.count === 0
            running: visible
        }

        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 4
            visible: !page.searching && results.count === 0
            icon.name: "mark-location"
            text: page.query === ""
                  ? i18nc("@info", "Search for your city")
                  : i18nc("@info", "No places found for “%1”", page.query)
            explanation: page.query === ""
                         ? i18nc("@info", "Type a place name; every weather provider is asked.")
                         : i18nc("@info", "Check the spelling, or try a larger town nearby.")
        }
    }
}
