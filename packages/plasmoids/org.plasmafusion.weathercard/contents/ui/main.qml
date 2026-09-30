/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support

import "../code/weather.js" as Weather

// Weather card of the Main board's desktop widgets: "Local weather" with the condition glyph,
// the temperature in Space Grotesk 42 px and "Partly cloudy · 21° / 12°". Data from the
// Plasma5Support weather engine (the providers of the stock weather widget). Without a
// location it shows a small "Set location" state that opens the location search.
PlasmoidItem {
    id: root

    // The Plasma style's card: frosted "blurred" widget background over the wallpaper blur.
    Plasmoid.backgroundHints: PlasmaCore.Types.StandardBackground
    preferredRepresentation: fullRepresentation
    // Text scale and pixel grid of the card (docs/parts/desktop-cards.md, "Text scale").
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
    }
    // Content box of the board card (192 x 122 minus the style's 14 px frame margins, which the
    // desktop's 16 px grid rounds to a 192 x 128 card), scaled with the text (the layout script
    // sizes the card the same way).
    // Always the card itself: switchWidth/switchHeight would show the icon whenever the card is
    // not larger than them (libplasma appletShouldBeExpanded).
    readonly property int boardWidth: 164
    readonly property int boardHeight: 94
    readonly property real contentWidth: m.px(boardWidth)
    readonly property real contentHeight: m.px(boardHeight)

    readonly property string source: Plasmoid.configuration.source
    readonly property bool configured: Weather.isSafeSource(source)
    // Last reply with weather in it for `source`: kept while a refresh is on its way, so the card
    // never falls back to "Updating…" once it has shown the weather.
    property var lastData: null
    readonly property var weather: configured ? lastData : null
    readonly property bool hasData: weather !== null

    // Fahrenheit only where the region uses US units (the stock widget also takes °F for the
    // United Kingdom's "imperial" measurement system, whose weather reports use °C).
    readonly property bool metric: Qt.locale().measurementSystem !== Locale.ImperialUSSystem
    readonly property int displayUnit: Weather.displayUnit(Plasmoid.configuration.temperatureUnit, metric)
    readonly property int dataUnit: hasData ? Number(weather["Temperature Unit"]) : 0
    readonly property var today: hasData ? Weather.highLow(weather) : ({ high: NaN, low: NaN })
    readonly property var day0: hasData ? Weather.forecastDay(weather, 0) : null

    readonly property string temperature: {
        if (!hasData) {
            return "";
        }
        const now = Weather.degrees(weather["Temperature"], dataUnit, displayUnit);
        if (now !== "") {
            return now;
        }
        // No observation (some stations): the forecast's value for the current period.
        return Weather.degrees(isNaN(today.high) ? today.low : today.high, dataUnit, displayUnit);
    }
    readonly property string condition: {
        if (!hasData) {
            return "";
        }
        const text = weather["Current Conditions"] || (day0 ? day0.summary : "");
        return Weather.sentenceCase(text, Qt.locale().name.startsWith("en"));
    }
    readonly property string highLowText: {
        const high = Weather.degrees(today.high, dataUnit, displayUnit);
        const low = Weather.degrees(today.low, dataUnit, displayUnit);
        if (high !== "" && low !== "") {
            return i18nc("@label today's high / low temperature, e.g. 21° / 12°", "%1 / %2", high, low);
        }
        if (high !== "") {
            return i18nc("@label today's high temperature", "High %1", high);
        }
        if (low !== "") {
            return i18nc("@label tonight's low temperature", "Low %1", low);
        }
        return "";
    }
    readonly property string glyph: {
        if (!hasData) {
            return "cloud";
        }
        return Weather.glyphFor(weather["Condition Icon"]) || Weather.glyphFor(day0 ? day0.icon : "") || "cloud";
    }
    readonly property string placeName: (hasData && weather["Place"]) || Plasmoid.configuration.placeDisplayName
    readonly property string title: Plasmoid.configuration.titleMode === 1 && placeName !== ""
                                    ? Weather.shortPlace(placeName)
                                    : i18nc("@title weather card", "Local weather")

    // No reply for a while (offline, provider down): say so instead of "Updating…" forever.
    property bool timedOut: false
    Timer {
        id: timeout
        interval: 45000
        onTriggered: root.timedOut = !root.hasData
    }
    onHasDataChanged: if (hasData) timedOut = false

    Plasmoid.icon: hasData ? (weather["Condition Icon"] || "weather-clouds") : "weather-clouds"
    toolTipMainText: placeName
    toolTipSubText: hasData ? [condition, temperature].filter(s => s !== "").join(" ") : ""

    // Direct delivery (interval 0): with a polling interval the engine's relay can swallow the
    // first real reply after an early empty one until the next poll (plasma5support
    // SignalRelay::checkQueueing), which left a newly chosen place on "Updating…" for the whole
    // interval. Updates are asked for by reconnecting the source instead (refreshTimer).
    P5Support.DataSource {
        id: weatherData
        engine: "weather"
        interval: 0
        onNewData: (sourceName, data) => {
            if (sourceName === root.connectedSource && Weather.hasWeather(data)) {
                root.lastData = data;
                root.timedOut = false;
            }
        }
    }

    // The source is connected only after isSafeSource() accepted it (see weather.js).
    property string connectedSource: ""
    function reconnect(): void {
        if (connectedSource !== "") {
            weatherData.disconnectSource(connectedSource);
        }
        if (connectedSource !== source) {
            lastData = null;
        }
        connectedSource = "";
        timedOut = false;
        reconnectDelay.stop();
        // Checked here, not through `configured`: this runs from onSourceChanged, possibly before
        // that binding has seen the new source (from no location to a first one).
        if (Weather.isSafeSource(source)) {
            // The engine drops an unused source 10 ms after the last disconnect; connecting later
            // than that makes it fetch again instead of handing back the cached reply.
            reconnectDelay.restart();
        }
    }
    Timer {
        id: reconnectDelay
        interval: 250
        onTriggered: {
            if (!Weather.isSafeSource(root.source)) {
                return;
            }
            root.connectedSource = root.source;
            weatherData.connectSource(root.source);
            timeout.restart();
        }
    }
    Timer {
        id: refreshTimer
        interval: Math.max(10, Plasmoid.configuration.updateInterval) * 60 * 1000
        running: root.configured
        repeat: true
        onTriggered: root.reconnect()
    }
    onSourceChanged: reconnect()
    Component.onCompleted: reconnect()

    function openSettings(): void {
        Plasmoid.internalAction("configure").trigger();
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action", "Refresh")
            icon.name: "view-refresh"
            visible: root.configured
            onTriggered: root.reconnect()
        },
        PlasmaCore.Action {
            text: i18nc("@action", "Open Forecast Website")
            icon.name: "internet-services"
            // Only the provider's web page (http or https), never another kind of URL.
            visible: root.hasData && /^https?:\/\//.test(String(root.weather["Credit Url"] || ""))
            onTriggered: Qt.openUrlExternally(String(root.weather["Credit Url"]))
        }
    ]

    fullRepresentation: FocusScope {
        id: card

        // The minimum never exceeds the board size: the desktop keeps a widget at least as large
        // as its minimum and stores the enlarged geometry, so a text size seen only for a moment
        // (the shell's font while a Global Theme is being applied) would grow the card for good.
        // The layout script gives the card the scaled size (docs/parts/desktop-cards.md).
        Layout.minimumWidth: Math.min(root.contentWidth, root.boardWidth)
        Layout.minimumHeight: Math.min(root.contentHeight, root.boardHeight)
        Layout.preferredWidth: root.contentWidth
        Layout.preferredHeight: root.contentHeight
        // 1 px of slack: the snapped sizes at fractional scales are a fraction of a pixel larger.
        readonly property real fitScale: Math.min(1, (width + 1) / root.contentWidth, (height + 1) / root.contentHeight)

        CardPalette { id: cardPalette }

        Accessible.role: Accessible.StaticText
        Accessible.name: root.hasData
            ? [root.title, root.temperature, root.condition, root.highLowText].filter(s => s !== "").join(", ")
            : root.title

        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            active: root.hasData
            mainText: root.placeName
            subText: root.hasData ? (root.weather["Credit"] || "") : ""
        }

        ColumnLayout {
            id: column
            // Board: 16 px padding + 1 px edge from the card side (the style's frame gives 14).
            // Laid out across the card; when the desktop gave the card less than this text size
            // needs (the text size was raised after the layout was made), laid out at the size
            // it needs and scaled down to fit, so nothing is cut off.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: (card.fitScale < 1 ? root.contentWidth : parent.width) - 2 * 3
            scale: card.fitScale
            spacing: m.px(6)

            // "Local weather" and the condition glyph.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: m.px(22)
                spacing: m.px(8)
                CardText {
                    pal: cardPalette
                    metrics: m
                    Layout.fillWidth: true
                    px: 12
                    weight: 700
                    color: cardPalette.label
                    text: root.title
                }
                WeatherGlyph {
                    size: m.px(22)
                    color: cardPalette.weatherIcon
                    condition: root.glyph
                }
            }

            // Temperature: Space Grotesk 42 px / 600 on a 42 px line (CSS line-height 1).
            Item {
                visible: root.configured
                Layout.fillWidth: true
                Layout.preferredHeight: m.px(42)
                CardText {
                    pal: cardPalette
                    metrics: m
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    display: true
                    px: 42
                    weight: 600
                    text: root.hasData && root.temperature !== "" ? root.temperature : "--°"
                    opacity: root.hasData ? 1 : 0.45
                }
            }

            CardText {
                visible: root.configured
                pal: cardPalette
                metrics: m
                Layout.fillWidth: true
                px: 12
                color: cardPalette.body
                text: {
                    if (root.hasData) {
                        return [root.condition, root.highLowText].filter(s => s !== "").join(" · ");
                    }
                    return root.timedOut ? i18nc("@info", "Weather unavailable") : i18nc("@info", "Updating…");
                }
            }

            // Without a location: a small button that opens the location search.
            SetupButton {
                id: setupButton
                visible: !root.configured
                pal: cardPalette
                metrics: m
                Layout.topMargin: m.px(4)
                text: i18nc("@action:button", "Set location")
                onTriggered: root.openSettings()
            }
            CardText {
                visible: !root.configured
                pal: cardPalette
                metrics: m
                Layout.fillWidth: true
                px: 12
                color: cardPalette.body
                text: i18nc("@info weather card without a location", "No location yet")
            }
        }
    }
}
