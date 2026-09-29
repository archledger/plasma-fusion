// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.private.mpris as Mpris

// The current MPRIS player (the same multiplexer the Media Player applet follows).
Item {
    id: media

    readonly property var player: mpris.currentPlayer
    readonly property bool available: !!player && player.playbackStatus > Mpris.PlaybackStatus.Stopped
    readonly property string track: player ? (player.track || "") : ""
    readonly property string artist: player ? (player.artist || "") : ""
    readonly property string identity: player ? (player.identity || "") : ""
    readonly property string artUrl: player ? (player.artUrl || "") : ""
    // The player's application icon. libkmpris falls back to a generic symbolic note when
    // it cannot read the player's desktop file; the desktop entry name is then tried as an
    // icon name (icon themes such as PlasmaFusion carry app icons by that name).
    readonly property string genericIcon: "emblem-music-symbolic"
    readonly property string iconName: {
        if (!player) {
            return "";
        }
        const icon = String(player.iconName || "");
        if (icon.length > 0 && icon !== genericIcon) {
            return icon;
        }
        return String(player.desktopEntry || "") || icon || genericIcon;
    }
    readonly property bool playing: !!player && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property bool canControl: !!player && player.canControl
    readonly property bool canPrevious: !!player && player.canGoPrevious
    readonly property bool canNext: !!player && player.canGoNext
    readonly property bool canPlayPause: !!player && (playing ? player.canPause : player.canPlay)
    readonly property bool canRaise: !!player && player.canRaise

    function previous() {
        if (player) {
            player.Previous();
        }
    }
    function next() {
        if (player) {
            player.Next();
        }
    }
    function playPause() {
        if (player) {
            player.PlayPause();
        }
    }
    function raise() {
        if (player && player.canRaise) {
            player.Raise();
        }
    }

    Mpris.Mpris2Model {
        id: mpris
    }
}
