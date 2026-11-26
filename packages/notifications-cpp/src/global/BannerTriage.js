/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    The rules of the banner keyboard triage, kept apart from the popup's items so that they can be
    tested: which banner the shortcut takes, how one banner's interaction moves between its
    states, and what Escape and Enter do on it. The applet applies them; KWin decides whether the
    shortcut is dispatched and which window has focus.
*/

.pragma library

const STATE_IDLE = "idle";
const STATE_REQUESTED = "requested";
const STATE_ACTIVE = "active";

// The newest banner that is visible and may be taken, by the time it was created; the later one
// when two share a time. -1 when there is none.
function newestBannerIndex(banners)
{
    let best = -1;
    let newest = -Infinity;
    for (let index = 0; index < banners.length; ++index) {
        const banner = banners[index];
        if (!banner.visible || !banner.eligible) {
            continue;
        }
        if (banner.created >= newest) {
            newest = banner.created;
            best = index;
        }
    }
    return best;
}

// How the interaction with one banner moves: idle, then requested when the shortcut is pressed,
// then active when KWin gives the banner keyboard focus, then idle again. Only a replacement that
// ends a focused interaction gives the previous window its focus back; everything else leaves
// focus to KWin.
function transition(state, event)
{
    switch (event) {
    case "request":
        return { state: state === STATE_IDLE ? STATE_REQUESTED : state, restoreFocus: false };
    case "granted":
        return { state: state === STATE_REQUESTED ? STATE_ACTIVE : state, restoreFocus: false };
    case "lost": // the banner's window is no longer active, or the screen locked
    case "hidden": // the banner went away by itself
    case "not-granted": // KWin did not focus the banner in time
        return { state: STATE_IDLE, restoreFocus: false };
    case "replaced": // the same popup now shows another notification
        return { state: STATE_IDLE, restoreFocus: state === STATE_ACTIVE };
    default:
        return { state: state, restoreFocus: false };
    }
}

// "dismiss" while the interaction is active, unless the reply field has the keyboard: there Escape
// keeps its stock behaviour, so a draft is not lost. "" when the key is not ours.
function escapeAction(interactionActive, replying)
{
    return interactionActive && !replying ? "dismiss" : "";
}

// "activate" runs the default action, once per interaction and never on a held key. "consume" is a
// key of ours that does nothing. "" when the key is not ours.
function enterAction(interactionActive, hasDefaultAction, spent, autoRepeat)
{
    if (!interactionActive) {
        return "";
    }
    if (autoRepeat || spent || !hasDefaultAction) {
        return "consume";
    }
    return "activate";
}
