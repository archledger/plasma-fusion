// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.private.mpris as Mpris

// The music playing, for the island (board Island.dc.html): the current MPRIS player, the same
// multiplexer the Media Player applet and quick settings follow (loaded with a Loader: optional).
// The island shows it only while it plays.
Item {
    id: media

    readonly property var player: mpris.currentPlayer
    readonly property bool playing: !!player && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property string track: player ? (player.track || "") : ""
    readonly property string artist: player ? (player.artist || "") : ""
    readonly property string identity: player ? (player.identity || "") : ""
    readonly property string artUrl: player ? (player.artUrl || "") : ""
    // The player's application icon; libkmpris falls back to a generic note when it cannot read
    // the player's desktop file, then the desktop entry name is tried as an icon name.
    readonly property string iconName: {
        if (!player) {
            return "";
        }
        const icon = String(player.iconName || "");
        if (icon.length > 0 && icon !== "emblem-music-symbolic") {
            return icon;
        }
        return String(player.desktopEntry || "") || icon;
    }
    readonly property bool canPrevious: !!player && player.canGoPrevious
    readonly property bool canNext: !!player && player.canGoNext
    readonly property bool canPlayPause: !!player && (playing ? player.canPause : player.canPlay)
    // Position and length in microseconds, as MPRIS gives them.
    readonly property double length: player ? player.length : 0
    readonly property double position: player ? player.position : 0
    function updatePosition() {
        if (player) {
            player.updatePosition();
        }
    }
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

    Mpris.Mpris2Model {
        id: mpris
    }
}
