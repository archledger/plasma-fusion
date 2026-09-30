/*
    SPDX-FileCopyrightText: 2016 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris

// Lock board, bottom left: the media card (300 x 72 glass, radius 18). Album art or the
// player's icon, title and state, previous/next when the player offers them and the round
// play/pause button. Shown only while a player exists.
Item {
    id: media

    property Backdrop backdrop: null
    // Text scale and pixel grid of the lock screen window (bound by LockScreenUi once loaded;
    // board sizes until then).
    property FusionMetrics metrics: null
    function px(v: real): real {
        return metrics ? metrics.px(v) : v;
    }
    function font(v: real): real {
        return metrics ? metrics.font(v) : v;
    }

    signal interacted()

    readonly property bool hasPlayer: repeater.count > 0

    implicitWidth: repeater.count > 0 && repeater.itemAt(0) ? repeater.itemAt(0).implicitWidth : 0
    implicitHeight: px(72)
    visible: hasPlayer

    Repeater {
        id: repeater
        model: Mpris.MultiplexerModel { }

        GlassPanel {
            id: card

            required property var model

            readonly property string track: model.track ?? ""
            readonly property string artist: model.artist ?? ""
            readonly property string identity: model.identity ?? ""
            // MultiplexerModel reports its own "emblem-favorite" as iconName; the active
            // player's icon (from its desktop file) is on the container.
            readonly property string iconName: model.container && model.container.iconName ? model.container.iconName : ""
            readonly property string desktopEntry: model.desktopEntry ?? ""
            readonly property url artUrl: model.artUrl ?? ""
            readonly property int playbackStatus: model.playbackStatus ?? Mpris.PlaybackStatus.Unknown
            readonly property bool canControl: model.canControl ?? false
            readonly property bool canGoNext: model.canGoNext ?? false
            readonly property bool canGoPrevious: model.canGoPrevious ?? false

            // The player's own icon: the one named by its desktop file, else its desktop-entry id
            // (most icon themes name application icons that way), else a generic note.
            readonly property string appIcon: iconName.length > 0 && iconName !== "emblem-music-symbolic" && iconName !== "emblem-favorite" ? iconName
                                            : desktopEntry.length > 0 ? desktopEntry : "emblem-music-symbolic"
            readonly property bool playing: playbackStatus === Mpris.PlaybackStatus.Playing
            readonly property bool paused: playbackStatus === Mpris.PlaybackStatus.Paused
            readonly property bool showSkip: canGoNext || canGoPrevious
            readonly property string title: track.length > 0 ? track
                : (identity.length > 0 ? identity : i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "No media playing"))
            readonly property string subtitle: {
                const parts = [];
                if (track.length > 0) {
                    parts.push(artist.length > 0 ? artist : identity);
                }
                if (paused) {
                    parts.push(i18nd("plasma_shell_org.plasmafusion.lockshell", "Paused"));
                } else if (playbackStatus === Mpris.PlaybackStatus.Stopped) {
                    parts.push(i18nd("plasma_shell_org.plasmafusion.lockshell", "Stopped"));
                } else if (track.length === 0) {
                    parts.push(i18nd("plasma_shell_org.plasmafusion.lockshell", "Playing"));
                }
                return parts.filter(p => p.length > 0).join(" · ");
            }

            backdrop: media.backdrop
            radius: 18
            width: implicitWidth
            height: media.px(72)
            implicitWidth: media.px(showSkip ? 348 : 300)
            enabled: canControl

            Accessible.role: Accessible.Grouping
            Accessible.name: title + (subtitle.length > 0 ? ", " + subtitle : "")

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: media.px(12)
                anchors.rightMargin: media.px(12)
                spacing: media.px(12)

                Item {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44

                    Image {
                        id: albumArt
                        anchors.fill: parent
                        visible: false
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        source: card.artUrl
                        sourceSize.width: 44 * Screen.devicePixelRatio
                        sourceSize.height: 44 * Screen.devicePixelRatio
                    }
                    Kirigami.ShadowedTexture {
                        anchors.fill: parent
                        visible: albumArt.status === Image.Ready
                        radius: 10
                        color: "transparent"
                        source: albumArt
                    }
                    Kirigami.Icon {
                        anchors.fill: parent
                        visible: albumArt.status !== Image.Ready
                        source: card.appIcon
                        fallback: "emblem-music-symbolic"
                        roundToIconSize: false
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: media.px(2)

                    Text {
                        Layout.fillWidth: true
                        text: card.title
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: PfStyle.text
                        font.family: PfStyle.uiFont
                        font.pixelSize: media.font(13)
                        font.weight: Font.DemiBold
                        font.styleName: PfStyle.extraBold
                        textFormat: Text.PlainText
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: card.subtitle
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: PfStyle.textSecondary
                        font.family: PfStyle.uiFont
                        font.pixelSize: media.font(12)
                        textFormat: Text.PlainText
                    }
                }

                RoundButton {
                    visible: card.showSkip
                    enabled: card.canGoPrevious
                    opacity: enabled ? 1 : 0.4
                    implicitWidth: 30
                    implicitHeight: 30
                    iconSize: 16
                    glyphPath: LayoutMirroring.enabled ? PfStyle.glyphNext : PfStyle.glyphPrevious
                    foreground: PfStyle.text
                    text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button Accessible only", "Previous track")
                    onClicked: {
                        media.interacted();
                        card.model.container.Previous();
                    }
                }

                RoundButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    iconSize: 16
                    fillColor: PfStyle.playFill
                    hoverFillColor: "#ffffff"
                    foreground: PfStyle.playGlyph
                    glyphPath: card.playing ? PfStyle.glyphPause : PfStyle.glyphPlay
                    text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button Accessible only", "Play or Pause media")
                    onClicked: {
                        media.interacted();
                        card.model.container.PlayPause();
                    }
                }

                RoundButton {
                    visible: card.showSkip
                    enabled: card.canGoNext
                    opacity: enabled ? 1 : 0.4
                    implicitWidth: 30
                    implicitHeight: 30
                    iconSize: 16
                    glyphPath: LayoutMirroring.enabled ? PfStyle.glyphPrevious : PfStyle.glyphNext
                    foreground: PfStyle.text
                    text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button Accessible only", "Next track")
                    onClicked: {
                        media.interacted();
                        card.model.container.Next();
                    }
                }
            }
        }
    }
}
