// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.private.mpris as Mpris

// The current MPRIS player (the same multiplexer the Media Player applet follows).
Item {
    id: media

    readonly property var player: mpris.currentPlayer
    // A player that plays or is paused; also a stopped one the user chose (the player row) while it
    // can play, so the card and its row stay to play it or choose another.
    readonly property bool available: !!player && (player.playbackStatus > Mpris.PlaybackStatus.Stopped
                                                   || (mpris.currentIndex > 0 && player.canPlay))
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
    // The players (the stock Media Player widget's tabs): rows of Mpris2Model, the first one the
    // automatic choice when there are several (roles identity, iconName, isMultiplexer).
    readonly property var playersModel: mpris
    readonly property int currentIndex: mpris.currentIndex
    function choosePlayer(i: int) {
        mpris.currentIndex = i;
    }
    // Position and length in microseconds, as MPRIS gives them.
    readonly property bool canSeek: !!player && player.canSeek
    readonly property double length: player ? player.length : 0
    readonly property double position: player ? player.position : 0
    function seek(us: double) {
        if (player && player.canSeek) {
            player.position = us;
        }
    }
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
    function raise() {
        if (player && player.canRaise) {
            player.Raise();
        }
    }

    Mpris.Mpris2Model {
        id: mpris
    }
}
