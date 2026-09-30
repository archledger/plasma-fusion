/*
    Plasma Fusion settings module: the "Appearance" page of the Main / MainLight boards.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    // Board content area: padding 20 px 24 px, sections 18 px apart.
    topPadding: 20
    bottomPadding: 20
    leftPadding: 24
    rightPadding: 24

    // Errors of the last Apply. The close button hides the message by setting visible = false,
    // which would break a binding, so visibility follows errorText through a handler: a new
    // error shows again after the previous one was closed.
    header: Kirigami.InlineMessage {
        id: errorMessage
        position: Kirigami.InlineMessage.Position.Header
        type: Kirigami.MessageType.Error
        text: kcm.errorText
        showCloseButton: true
        visible: false
        Component.onCompleted: visible = kcm.errorText !== ""

        Connections {
            target: kcm
            function onErrorTextChanged() {
                errorMessage.visible = kcm.errorText !== "";
            }
        }
    }

    // kcm.style, kcm.accentMode and kcm.buttonStyle values (PlasmaFusionKcm enums).
    readonly property int styleLight: 0
    readonly property int styleDark: 1
    readonly property int styleSunset: 2
    readonly property int accentScheme: 0
    readonly property int accentCustom: 1
    readonly property int accentWallpaper: 2

    // The page's content item always gets the full width; the board's column is 420 px, so the
    // controls stop growing at 560 px in a wide System Settings window (left-aligned, as on the board).
    // In a narrow window the cards and swatches wrap and the segmented control shrinks to its
    // text, so nothing needs horizontal scrolling down to that width.
    Item {
        implicitHeight: page.implicitHeight
        implicitWidth: buttonsControl.minimumWidth

        ColumnLayout {
            id: page
            spacing: 18
            width: Math.min(parent.width, 560)

            FusionPalette {
                id: fusionPalette
            }

            // ---------- Style ----------
            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                SectionTitle {
                    text: i18nc("@title:group", "Style")
                    pal: fusionPalette
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 12
                    Accessible.role: Accessible.Grouping
                    Accessible.name: i18nc("@title:group", "Style")

                    StyleCard {
                        pal: fusionPalette
                        variant: 0
                        text: i18nc("@option:radio Plasma Fusion Light", "Light")
                        selected: kcm.style === root.styleLight
                        onClicked: kcm.style = root.styleLight
                    }
                    StyleCard {
                        pal: fusionPalette
                        variant: 1
                        text: i18nc("@option:radio Plasma Fusion Dark", "Dark")
                        selected: kcm.style === root.styleDark
                        onClicked: kcm.style = root.styleDark
                    }
                    StyleCard {
                        pal: fusionPalette
                        variant: 2
                        text: i18nc("@option:radio switch between light and dark with the time of day", "Follow sunset")
                        selected: kcm.style === root.styleSunset
                        onClicked: kcm.style = root.styleSunset
                        QQC2.ToolTip.text: i18nc("@info:tooltip", "Light during the day, dark after sunset")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }
            }

            // ---------- Accent color ----------
            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                SectionTitle {
                    text: i18nc("@title:group", "Accent color")
                    pal: fusionPalette
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 10
                    Accessible.role: Accessible.Grouping
                    Accessible.name: i18nc("@title:group", "Accent color")

                    // Board swatches. Blue is the colour schemes' own accent (#2f6fdf); the others
                    // are written as the accent color.
                    Repeater {
                        model: [
                            { name: i18nc("@option:radio accent color", "Blue"), color: "#5b9dff", scheme: true },
                            { name: i18nc("@option:radio accent color", "Teal"), color: "#3cc4b0", scheme: false },
                            { name: i18nc("@option:radio accent color", "Green"), color: "#3aa65b", scheme: false },
                            { name: i18nc("@option:radio accent color", "Amber"), color: "#f2a65a", scheme: false },
                            { name: i18nc("@option:radio accent color", "Orange"), color: "#e8743b", scheme: false },
                            { name: i18nc("@option:radio accent color", "Pink"), color: "#d6457a", scheme: false },
                            { name: i18nc("@option:radio accent color", "Violet"), color: "#9b7bf0", scheme: false }
                        ]
                        delegate: Swatch {
                            required property var modelData
                            pal: fusionPalette
                            color: modelData.color
                            text: modelData.name
                            selected: modelData.scheme
                                ? kcm.accentMode === root.accentScheme
                                : (kcm.accentMode === root.accentCustom && Qt.colorEqual(kcm.accentColor, modelData.color))
                            onClicked: {
                                if (modelData.scheme) {
                                    kcm.setSchemeAccent();
                                } else {
                                    kcm.setCustomAccent(modelData.color);
                                }
                            }
                        }
                    }
                    WallpaperPill {
                        pal: fusionPalette
                        text: i18nc("@option:radio take the accent color from the wallpaper", "From wallpaper")
                        selected: kcm.accentMode === root.accentWallpaper
                        wallpaperColor: kcm.accentMode === root.accentWallpaper ? kcm.accentColor : "transparent"
                        onClicked: kcm.setWallpaperAccent()
                    }
                }
            }

            // ---------- Window buttons ----------
            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                SectionTitle {
                    text: i18nc("@title:group title bar buttons", "Window buttons")
                    pal: fusionPalette
                }
                Segmented {
                    id: buttonsControl
                    Layout.fillWidth: true
                    pal: fusionPalette
                    accessibleName: i18nc("@title:group title bar buttons", "Window buttons")
                    model: [
                        i18nc("@option:radio buttons on the right with symbols", "Right · glyphs"),
                        i18nc("@option:radio small round buttons on the left", "Left · circles"),
                        i18nc("@option:radio buttons appear when the pointer is on the title bar", "Show on hover")
                    ]
                    currentIndex: kcm.buttonStyle
                    onActivated: index => kcm.buttonStyle = index
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: kcm.decorationInstalled && !kcm.fusionDecoration
                    spacing: 10
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.family: fusionPalette.family
                        font.pointSize: 8.625 // 11.5 px (pixelSize is an integer)
                        color: fusionPalette.section
                        text: i18nc("@info", "Windows use another title bar. The Plasma Fusion window decoration is installed.")
                    }
                    QQC2.Button {
                        text: i18nc("@action:button use the Plasma Fusion window decoration", "Use It")
                        onClicked: kcm.useFusionDecoration()
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: kcm.buttonStyle === 2 && !kcm.decorationInstalled
                    wrapMode: Text.WordWrap
                    font.family: fusionPalette.family
                    font.pointSize: 8.625 // 11.5 px (pixelSize is an integer)
                    color: fusionPalette.section
                    text: i18nc("@info", "The buttons stay visible until the Plasma Fusion window decoration is installed.")
                }
            }

            // ---------- Toggles ----------
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true

                ToggleRow {
                    Layout.fillWidth: true
                    pal: fusionPalette
                    text: i18nc("@option:check", "Magnify dock icons on hover")
                    checked: kcm.magnify
                    enabled: kcm.dockAvailable && !kcm.shellLoading
                    note: kcm.shellLoading || kcm.dockAvailable ? ""
                        : kcm.shellRunning ? i18nc("@info", "The Plasma Fusion dock is not in a panel.")
                        : i18nc("@info", "The Plasma desktop is not running. The setting is read when it starts.")
                    onToggleRequested: kcm.magnify = !kcm.magnify
                }
                ToggleRow {
                    Layout.fillWidth: true
                    pal: fusionPalette
                    text: i18nc("@option:check", "Global menu in the top bar")
                    checked: kcm.globalMenu
                    enabled: kcm.topBarAvailable && !kcm.shellLoading
                    note: kcm.shellLoading || kcm.topBarAvailable ? ""
                        : kcm.shellRunning ? i18nc("@info", "The Plasma Fusion top bar is not on this desktop.")
                        : i18nc("@info", "The Plasma desktop is not running. The setting is read when it starts.")
                    onToggleRequested: kcm.globalMenu = !kcm.globalMenu
                }
                ToggleRow {
                    Layout.fillWidth: true
                    pal: fusionPalette
                    last: true
                    text: i18nc("@option:check the top-left screen corner opens Overview", "Hot corner opens Overview")
                    checked: kcm.hotCorner
                    onToggleRequested: kcm.hotCorner = !kcm.hotCorner
                }
            }
        }
    }
}
