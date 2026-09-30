/*
    Plasma Fusion log-in splash (design/boards/Splash.dc.html).

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    ksplashqml sets `stage` as start-up proceeds: 1 initial, 2 window manager (set at once on
    Wayland), then one step each for startplasma, kcminit and ksmserver (3-5); the sixth step,
    the desktop, closes the splash. The progress bar shows the finished share of those steps
    (stage 5 = 80 %) and creeps towards the next one while a step takes long.
*/
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.coreaddons as KCoreAddons

Rectangle {
    id: root

    property int stage

    // Board colours.
    readonly property color textColor: "#e8ebf4"
    readonly property color secondaryTextColor: "#8f98b3"
    readonly property color accentColor: "#5b9dff"
    readonly property bool animate: Kirigami.Units.longDuration > 1

    color: "#0b0e1b"

    // The emblem and its place scale with the screen, as on the board at 1440 x 900 (ADAPTIVE
    // 5.11): 380 px x clamp(min(W / 1440, H / 900), 0.75, 1.4).
    readonly property real emblemScale: Math.max(0.75, Math.min(1.4, Math.min(width / 1440, height / 900)))

    // Fraction of the bar for each stage; the bar never runs backwards.
    readonly property real stageProgress: stage <= 1 ? 0.05 : Math.min(1, (stage - 1) / 5)
    readonly property real nextStageProgress: stage <= 1 ? 0.2 : Math.min(1, stage / 5)
    property real creep: 0

    // Text scale and pixel grid of the splash window (docs/parts/lookandfeel.md, "Text scale"):
    // the greeting, the status line and their gap follow the user's text size; the emblem,
    // the progress bar and the mark do not.
    FusionMetrics {
        id: m
        area: Qt.rect(0, 0, root.width, root.height)
    }

    // Manrope and Space Grotesk are installed as one static file per weight (the build's
    // fonts/*/static), so the CSS weight is the font weight and Qt draws no synthetic bold.
    // Without the font installed, the Plasma UI font (FusionMetrics) gets the same weight.
    component FusionText: Text {
        property bool display: false
        property int weight: 400
        font.family: display ? m.displayFamily : m.family
        font.weight: weight
        renderType: Text.QtRendering
        textFormat: Text.PlainText
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    onStageChanged: {
        if (stage >= 2 && content.opacity === 0) {
            introAnimation.running = true;
        }
        creepAnimation.restart();
    }
    Component.onCompleted: {
        if (stage >= 2) {
            introAnimation.running = true;
        }
    }

    NumberAnimation {
        id: creepAnimation
        target: root
        property: "creep"
        from: 0
        to: 0.6
        duration: 6000
        easing.type: Easing.OutCubic
    }

    // Pre-blurred Dusk Ridge wallpaper (generated from the board at build time); on a portrait
    // screen the portrait render, which keeps the sun in view.
    Image {
        anchors.fill: parent
        source: root.height > root.width ? "images/background-portrait.png" : "images/background.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
        smooth: true
    }

    KCoreAddons.KUser {
        id: user
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        // Logo, rings and orbiting dots; centred 70 px above the middle of the screen (both at the
        // board's size; scaled about their centre with the screen).
        Item {
            id: emblem
            width: 380
            height: 380
            x: Math.round((root.width - width) / 2)
            y: Math.round(root.height / 2 - 70 * root.emblemScale - height / 2)
            scale: root.emblemScale

            Rectangle {
                anchors.centerIn: parent
                width: 240
                height: 240
                radius: width / 2
                color: "transparent"
                border.width: 1.5
                border.color: Qt.rgba(1, 1, 1, 0.06)
            }
            Rectangle {
                anchors.centerIn: parent
                width: 380
                height: 380
                radius: width / 2
                color: "transparent"
                border.width: 1.5
                border.color: Qt.rgba(1, 1, 1, 0.04)
            }

            // Three dots travelling along the outer ring together, so they keep the spacing of
            // the board (starting angles clockwise from 12 o'clock) and never run into each other.
            Repeater {
                model: [
                    { angle: 0, size: 10, colour: "#5b9dff", period: 16000 },
                    { angle: 70.1, size: 8, colour: "#f2a65a", period: 16000 },
                    { angle: 240, size: 8, colour: "#3cc4b0", period: 16000 }
                ]
                delegate: Item {
                    id: orbit
                    required property var modelData
                    anchors.fill: parent
                    rotation: modelData.angle

                    Rectangle {
                        x: (orbit.width - width) / 2
                        y: -height / 2
                        width: orbit.modelData.size
                        height: width
                        radius: width / 2
                        color: orbit.modelData.colour
                        antialiasing: true
                    }

                    RotationAnimator on rotation {
                        from: orbit.modelData.angle
                        to: orbit.modelData.angle + 360
                        duration: orbit.modelData.period
                        loops: Animation.Infinite
                        running: root.animate
                    }
                }
            }

            // Three overlapping circles, blended "screen" over the dark background on the
            // board; the blended colours are used directly.
            Repeater {
                model: [
                    { dx: 0, dy: -28, colour: "#63a3ff" },
                    { dx: -31, dy: 26, colour: "#f3ac6f" },
                    { dx: 31, dy: 26, colour: "#46c8ba" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: 92
                    height: 92
                    radius: 46
                    x: emblem.width / 2 + modelData.dx - 46
                    y: emblem.height / 2 + modelData.dy - 46
                    color: modelData.colour
                    antialiasing: true
                }
            }
        }

        Column {
            id: greeting
            x: 0
            y: Math.round(root.height / 2 + 160 * root.emblemScale)
            width: root.width
            spacing: m.px(18)

            FusionText {
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.textColor
                display: true
                weight: 600
                font.pixelSize: m.font(30)
                text: {
                    const name = (user.fullName || "").trim().split(/\s+/)[0] || user.loginName;
                    return name ? "Welcome back, " + name : "Welcome back";
                }
            }

            Rectangle {
                id: track
                anchors.horizontalCenter: parent.horizontalCenter
                width: 260
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.1)

                Accessible.role: Accessible.ProgressBar
                Accessible.name: "Loading desktop"

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: root.accentColor
                    width: Math.round(parent.width * Math.min(1, root.stageProgress
                                      + root.creep * (root.nextStageProgress - root.stageProgress)))
                    Behavior on width {
                        enabled: root.animate
                        SmoothedAnimation { velocity: 400 }
                    }
                }
            }

            FusionText {
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.secondaryTextColor
                font.pixelSize: m.font(13)
                text: {
                    switch (root.stage) {
                    case 3: return "Starting Plasma · loading settings";
                    case 4: return "Starting Plasma · starting services";
                    case 5: return "Starting Plasma · restoring your session";
                    default: return "Starting Plasma";
                    }
                }
            }
        }

        // "Plasma Fusion" mark, bottom-left.
        Row {
            x: 40
            y: root.height - 32 - height
            spacing: 10

            Item {
                width: 18
                height: 18
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    // The 24-unit logo drawn at 18 px.
                    model: [
                        { cx: 12, cy: 8.5, colour: "#5b9dff", opacity: 0.9 },
                        { cx: 8, cy: 15, colour: "#f2a65a", opacity: 0.9 },
                        { cx: 16, cy: 15, colour: "#3cc4b0", opacity: 0.85 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: 8.25
                        height: 8.25
                        radius: 4.125
                        x: modelData.cx * 0.75 - 4.125
                        y: modelData.cy * 0.75 - 4.125
                        color: modelData.colour
                        opacity: modelData.opacity
                        antialiasing: true
                    }
                }
            }

            FusionText {
                anchors.verticalCenter: parent.verticalCenter
                color: root.secondaryTextColor
                weight: 700
                font.pixelSize: m.font(13)
                text: "Plasma Fusion"
            }
        }
    }

    OpacityAnimator {
        id: introAnimation
        running: false
        target: content
        from: 0
        to: 1
        duration: root.animate ? 600 : 0
        easing.type: Easing.OutCubic
    }
}
