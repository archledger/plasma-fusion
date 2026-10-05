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

    // Errors of the last Apply or action, and the result of an action. The close button hides a
    // message by setting visible = false, which would break a binding, so visibility follows the
    // text through a handler: a new message shows again after the previous one was closed.
    header: ColumnLayout {
        spacing: 0

        Kirigami.InlineMessage {
            id: errorMessage
            Layout.fillWidth: true
            position: Kirigami.InlineMessage.Position.Header
            type: Kirigami.MessageType.Error
            text: kcm.errorText
            showCloseButton: true
            visible: false
            Component.onCompleted: visible = kcm.errorText !== ""
        }
        Kirigami.InlineMessage {
            id: infoMessage
            Layout.fillWidth: true
            position: Kirigami.InlineMessage.Position.Header
            type: Kirigami.MessageType.Positive
            text: kcm.infoText
            showCloseButton: true
            visible: false
            Component.onCompleted: visible = kcm.infoText !== ""
        }
        Connections {
            target: kcm
            function onErrorTextChanged() {
                errorMessage.visible = kcm.errorText !== "";
            }
            function onInfoTextChanged() {
                infoMessage.visible = kcm.infoText !== "";
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
    readonly property int glassFull: 0
    readonly property int glassReduced: 1
    readonly property int glassSolid: 2

    // The same note for every control that goes through the Plasma shell.
    function shellNote(available, missingText) {
        if (kcm.shellLoading || available) {
            return "";
        }
        return kcm.shellRunning ? missingText : i18nc("@info", "The Plasma desktop is not running. The setting is read when it starts.");
    }

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
                    note: kcm.dockAvailable && kcm.powerCritical
                        ? i18nc("@info", "Paused while the battery is at 10 % or less.")
                        : root.shellNote(kcm.dockAvailable, i18nc("@info", "The Plasma Fusion dock is not in a panel."))
                    onToggleRequested: kcm.magnify = !kcm.magnify
                }
                ToggleRow {
                    Layout.fillWidth: true
                    pal: fusionPalette
                    text: i18nc("@option:check", "Global menu in the top bar")
                    checked: kcm.globalMenu
                    enabled: kcm.topBarAvailable && !kcm.shellLoading
                    note: root.shellNote(kcm.topBarAvailable, i18nc("@info", "The Plasma Fusion top bar is not on this desktop."))
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

            // ---------- Below the board: the rest of the Plasma Fusion switches ----------

            // ---------- Windows ----------
            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                SectionTitle {
                    text: i18nc("@title:group", "Windows")
                    pal: fusionPalette
                }
                ChoiceRow {
                    Layout.fillWidth: true
                    pal: fusionPalette
                    last: true
                    text: i18nc("@label snap layout picker on the maximize button", "Snap layouts on maximize")
                    model: [
                        i18nc("@option:radio press and hold the maximize button", "Hold"),
                        i18nc("@option:radio rest the pointer on the maximize button", "Hover")
                    ]
                    currentIndex: kcm.snapTrigger
                    onActivated: index => kcm.snapTrigger = index
                    note: (kcm.snapTrigger === 0
                           ? i18nc("@info", "Hold the maximize button for half a second, or press Meta+Z. A click always maximizes.")
                           : i18nc("@info", "Resting the pointer on maximize opens the picker. While it is open, a click on maximize only closes it."))
                        + (kcm.fusionDecoration ? "" : " " + i18nc("@info", "Needs the Plasma Fusion title bars."))
                }
            }

            // ---------- Glass and motion ----------
            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                SectionTitle {
                    text: i18nc("@title:group transparency and animations", "Glass and motion")
                    pal: fusionPalette
                }
                Segmented {
                    Layout.fillWidth: true
                    pal: fusionPalette
                    accessibleName: i18nc("@title:group transparency level", "Glass")
                    model: [
                        i18nc("@option:radio frosted glass everywhere", "Full"),
                        i18nc("@option:radio solid bars, glass pop-ups", "Reduced"),
                        i18nc("@option:radio no transparency", "Solid")
                    ]
                    currentIndex: kcm.glass
                    enabled: kcm.shellRunning && !kcm.shellLoading
                    onActivated: index => kcm.glass = index
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.family: fusionPalette.family
                    font.pointSize: 8.625 * fusionPalette.m.ts // 11.5 px
                    color: fusionPalette.section
                    text: {
                        const notes = [
                            i18nc("@info", "Frosted glass on the bars and pop-ups; the top bar can turn solid next to windows."),
                            i18nc("@info", "The top bar and the dock are solid; pop-ups keep their glass."),
                            i18nc("@info", "No transparency anywhere.")
                        ];
                        let text = notes[kcm.glass] || "";
                        if (kcm.powerCritical) {
                            text += " " + i18nc("@info", "While the battery is at 10 % or less, the glass stays solid.");
                        }
                        const shell = root.shellNote(kcm.shellRunning, "");
                        return shell !== "" ? shell : text;
                    }
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    ToggleRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@option:check", "High contrast colors")
                        checked: kcm.highContrast
                        enabled: kcm.highContrastAvailable || kcm.highContrast
                        note: !kcm.highContrastAvailable && !kcm.highContrast
                            ? i18nc("@info", "The Plasma Fusion High Contrast colors are not installed.")
                            : kcm.highContrast && kcm.glass !== root.glassSolid
                                ? i18nc("@info", "Solid glass keeps text easiest to read with high contrast.")
                                : kcm.highContrast && kcm.style === root.styleSunset
                                    ? i18nc("@info", "Follow sunset switches back to the normal colors at dawn and dusk.")
                                    : ""
                        onToggleRequested: kcm.highContrast = !kcm.highContrast
                    }
                    ToggleRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        last: true
                        text: i18nc("@option:check", "Reduce motion")
                        checked: kcm.reduceMotion
                        note: i18nc("@info", "Windows and pop-ups appear at once. Dock magnification stays, without the zoom animation.")
                        onToggleRequested: kcm.reduceMotion = !kcm.reduceMotion
                    }
                }
            }

            // ---------- Dock and top bar ----------
            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                SectionTitle {
                    text: i18nc("@title:group", "Dock and top bar")
                    pal: fusionPalette
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    ChoiceRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@label size of the dock icon under the pointer", "Magnified icon size")
                        model: [i18nc("@option:radio icon size in pixels", "56 px"), i18nc("@option:radio icon size in pixels", "62 px")]
                        currentIndex: [56, 62].indexOf(kcm.magnifiedSize)
                        enabled: kcm.dockAvailable && !kcm.shellLoading && kcm.magnify
                        note: kcm.dockAvailable && !kcm.magnify ? i18nc("@info", "Magnification is off.")
                            : root.shellNote(kcm.dockAvailable, i18nc("@info", "The Plasma Fusion dock is not in a panel."))
                        onActivated: index => kcm.magnifiedSize = [56, 62][index]
                    }
                    ToggleRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@option:check", "Solid top bar next to windows")
                        checked: kcm.glass === root.glassReduced || kcm.solidTopBar
                        enabled: kcm.topBarAvailable && !kcm.shellLoading && kcm.glass !== root.glassReduced
                        note: kcm.topBarAvailable && kcm.glass === root.glassReduced
                            ? i18nc("@info", "With Reduced glass the top bar is always solid.")
                            : root.shellNote(kcm.topBarAvailable, i18nc("@info", "The Plasma Fusion top bar is not on this desktop."))
                        onToggleRequested: kcm.solidTopBar = !kcm.solidTopBar
                    }
                    ToggleRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        last: true
                        text: i18nc("@option:check", "Top bar on every screen")
                        checked: kcm.everyScreen
                        enabled: kcm.shellRunning && !kcm.shellLoading
                        note: kcm.shellRunning && !kcm.topBarScriptAvailable
                            ? i18nc("@info", "Other screens get their bar with the next Plasma Fusion layout update; the choice is kept.")
                            : root.shellNote(kcm.shellRunning, "")
                        onToggleRequested: kcm.everyScreen = !kcm.everyScreen
                    }
                }
            }

            // ---------- Desktop ----------
            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                SectionTitle {
                    text: i18nc("@title:group", "Desktop")
                    pal: fusionPalette
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    ToggleRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@option:check files of the Desktop folder on the desktop", "Icons on the desktop")
                        checked: kcm.desktopIcons
                        enabled: kcm.folderAvailable && !kcm.shellLoading
                        note: root.shellNote(kcm.folderAvailable, i18nc("@info", "This desktop shows no icons (it is not a Folder View desktop)."))
                        onToggleRequested: kcm.desktopIcons = !kcm.desktopIcons
                    }
                    ChoiceRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@label", "Icon size")
                        // Folder View's iconSize 1, 2, 3: 32, 48 and 64 px.
                        model: [
                            i18nc("@option:radio desktop icon size", "Small"),
                            i18nc("@option:radio desktop icon size", "Medium"),
                            i18nc("@option:radio desktop icon size", "Large")
                        ]
                        currentIndex: [1, 2, 3].indexOf(kcm.iconSize)
                        enabled: kcm.folderAvailable && !kcm.shellLoading && kcm.desktopIcons
                        onActivated: index => kcm.iconSize = [1, 2, 3][index]
                    }
                    ChoiceRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        last: true
                        text: i18nc("@label", "When I drag files between folders")
                        model: [
                            i18nc("@option:radio show the Move / Copy / Link menu", "Ask"),
                            i18nc("@option:radio move without asking", "Move")
                        ]
                        currentIndex: kcm.dndBehavior
                        note: kcm.dndBehavior === 1
                            ? i18nc("@info", "Files move without a menu when they stay on the same drive; other drops still ask.")
                            : ""
                        onActivated: index => kcm.dndBehavior = index
                    }
                }
            }

            // ---------- Icons ----------
            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                SectionTitle {
                    text: i18nc("@title:group", "Icons")
                    pal: fusionPalette
                }
                ChoiceRow {
                    Layout.fillWidth: true
                    pal: fusionPalette
                    last: true
                    text: i18nc("@label", "Application icons")
                    // plasmafusionrc [Icons] AppIcons: designs 0, familiar 1 (the default).
                    model: [
                        i18nc("@option:radio the designed Plasma Fusion tiles", "Designed tiles"),
                        i18nc("@option:radio the apps' own icons on Plasma Fusion tiles", "Real app icons")
                    ]
                    currentIndex: kcm.iconsMode
                    note: kcm.iconsMode === 0
                        ? i18nc("@info", "Only the designed Plasma Fusion tiles are shown; the icon service removes the apps' own icons it drew earlier.")
                        : i18nc("@info", "Every installed app's own icon is drawn on a Plasma Fusion tile and kept up to date as apps change.")
                    onActivated: index => kcm.iconsMode = index
                }
            }

            // ---------- Battery ----------
            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                SectionTitle {
                    text: i18nc("@title:group", "Battery")
                    pal: fusionPalette
                }
                ToggleRow {
                    Layout.fillWidth: true
                    pal: fusionPalette
                    text: i18nc("@option:check", "Lighter at 10 % battery")
                    checked: kcm.lighterOnCritical
                    note: i18nc("@info", "Solid glass and no dock magnification until the battery recovers.")
                    onToggleRequested: kcm.lighterOnCritical = !kcm.lighterOnCritical
                }
                ToggleRow {
                    Layout.fillWidth: true
                    pal: fusionPalette
                    last: true
                    text: i18nc("@option:check", "Search inside file contents")
                    checked: kcm.fileContentIndexing
                    note: i18nc("@info", "Lets search find words inside documents. Indexing already pauses on battery; turn it off to save power while charging. File names stay searchable.")
                    onToggleRequested: kcm.fileContentIndexing = !kcm.fileContentIndexing
                }
            }

            // ---------- Tablet ----------
            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                SectionTitle {
                    text: i18nc("@title:group laptop folded into a tablet", "Tablet")
                    pal: fusionPalette
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    ChoiceRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@label", "Tablet mode")
                        model: [
                            i18nc("@option:radio tablet mode follows the hinge", "Automatic"),
                            i18nc("@option:radio tablet mode", "Always"),
                            i18nc("@option:radio tablet mode", "Never")
                        ]
                        currentIndex: kcm.tabletMode
                        note: kcm.tabletModeActive ? i18nc("@info", "Now in tablet mode.")
                            : kcm.tabletModeAvailable ? i18nc("@info", "Now in laptop mode.")
                            : i18nc("@info", "This computer reports no tablet posture; Automatic keeps laptop mode.")
                        onActivated: index => kcm.tabletMode = index
                    }
                    ChoiceRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@label", "Apps in tablet mode")
                        model: [
                            i18nc("@option:radio apps fill the screen without title bars", "Full screen"),
                            i18nc("@option:radio apps keep their window frames", "Windowed")
                        ]
                        currentIndex: kcm.tabletApps
                        onActivated: index => kcm.tabletApps = index
                    }
                    ChoiceRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@label", "Dock in tablet mode")
                        model: [
                            i18nc("@option:radio the dock hides while an app is open", "Hide over apps"),
                            i18nc("@option:radio", "Always show")
                        ]
                        currentIndex: kcm.tabletDock
                        note: kcm.tabletDock === 0 ? i18nc("@info", "Swipe up from the bottom edge to bring it back.") : ""
                        onActivated: index => kcm.tabletDock = index
                    }
                    ChoiceRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@label", "On-screen keyboard")
                        model: [
                            i18nc("@option:radio on-screen keyboard", "Tablet mode"),
                            i18nc("@option:radio on-screen keyboard after a touch", "On touch"),
                            i18nc("@option:radio on-screen keyboard", "Never")
                        ]
                        currentIndex: kcm.keyboardPolicy
                        enabled: kcm.quickSettingsAvailable && !kcm.shellLoading
                        note: root.shellNote(kcm.quickSettingsAvailable, i18nc("@info", "Plasma Fusion quick settings are not in a panel."))
                        onActivated: index => kcm.keyboardPolicy = index
                    }
                    ToggleRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@option:check", "Swipe from the left edge opens the launcher")
                        checked: kcm.edgeLeft
                        onToggleRequested: kcm.edgeLeft = !kcm.edgeLeft
                    }
                    ToggleRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@option:check", "Swipe from the right edge opens quick settings")
                        checked: kcm.edgeRight
                        onToggleRequested: kcm.edgeRight = !kcm.edgeRight
                    }
                    ToggleRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        last: true
                        text: i18nc("@option:check line at the bottom over full-screen apps", "Home indicator")
                        checked: kcm.homeIndicator
                        enabled: kcm.dockAvailable && !kcm.shellLoading
                        note: root.shellNote(kcm.dockAvailable, i18nc("@info", "The Plasma Fusion dock is not in a panel."))
                        onToggleRequested: kcm.homeIndicator = !kcm.homeIndicator
                    }
                }
            }

            // ---------- Start over ----------
            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true

                RowLayout {
                    Layout.fillWidth: true
                    SectionTitle {
                        text: i18nc("@title:group", "Start over")
                        pal: fusionPalette
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    QQC2.BusyIndicator {
                        visible: kcm.busy
                        running: kcm.busy
                        Layout.preferredHeight: fusionPalette.m.px(16)
                        Layout.preferredWidth: fusionPalette.m.px(16)
                    }
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    ActionRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        text: i18nc("@label", "Restore my previous desktop")
                        description: kcm.previousDesktopAvailable
                            ? i18nc("@info", "The look you had before Plasma Fusion. Panels and desktop widgets stay as they are.")
                            : i18nc("@info", "No look from before Plasma Fusion was saved on this computer.")
                        buttonText: i18nc("@action:button", "Restore…")
                        buttonIcon: "edit-undo"
                        enabled: kcm.previousDesktopAvailable && !kcm.busy
                        onTriggered: restoreDialog.open()
                    }
                    ActionRow {
                        Layout.fillWidth: true
                        pal: fusionPalette
                        last: true
                        text: i18nc("@label", "Reset Fusion layout")
                        description: !kcm.shellRunning ? i18nc("@info", "The Plasma desktop is not running.")
                            : !kcm.fusionLookAndFeel ? i18nc("@info", "Choose Light, Dark or Follow sunset first.")
                            : i18nc("@info", "Rebuild the top bar, dock and desktop cards as Plasma Fusion sets them up.")
                        buttonText: i18nc("@action:button", "Reset…")
                        buttonIcon: "view-refresh"
                        enabled: kcm.shellRunning && kcm.fusionLookAndFeel && !kcm.busy
                        onTriggered: resetDialog.open()
                    }
                }
            }
        }
    }

    Kirigami.PromptDialog {
        id: restoreDialog
        title: i18nc("@title:window", "Restore Your Previous Desktop?")
        subtitle: i18nc("@info",
                        "The colors, icons, fonts, cursor, Plasma style and window decoration you had before Plasma Fusion come back. "
                        + "Panels and desktop widgets stay as they are. Plasma Fusion's lock screen, title bars and window tools switch off "
                        + "at your next login. Choosing Light or Dark here brings Plasma Fusion back.")
        standardButtons: Kirigami.Dialog.Cancel
        customFooterActions: [
            Kirigami.Action {
                text: i18nc("@action:button", "Restore")
                icon.name: "edit-undo"
                onTriggered: {
                    restoreDialog.close();
                    kcm.restorePreviousDesktop();
                }
            }
        ]
    }

    Kirigami.PromptDialog {
        id: resetDialog
        title: i18nc("@title:window", "Reset the Plasma Fusion Layout?")
        subtitle: i18nc("@info",
                        "The top bar, dock and desktop cards are rebuilt as Plasma Fusion sets them up. Pinned apps, widget settings and "
                        + "desktop icon positions go back to their defaults; your files stay where they are. The widgets keep their keyboard "
                        + "shortcuts.")
        standardButtons: Kirigami.Dialog.Cancel
        customFooterActions: [
            Kirigami.Action {
                text: i18nc("@action:button", "Reset Layout")
                icon.name: "view-refresh"
                onTriggered: {
                    resetDialog.close();
                    kcm.resetLayout();
                }
            }
        ]
    }
}
