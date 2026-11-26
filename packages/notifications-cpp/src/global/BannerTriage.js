/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    The rules of the banner keyboard triage, kept apart from the popup's items so that they can be
    tested: which banner the shortcut takes, which window had the keyboard focus before it, how
    one banner's interaction moves between its states, and what Escape and Enter do on it. The
    applet applies them; KWin decides whether the shortcut is dispatched and which window has focus.
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

// The window that has the keyboard focus when the shortcut is pressed, as the task model names
// it: [row] for a window of its own; in a group of windows [row, child], the window itself and
// not the group, which cannot be activated. Of several windows marked active the one highest in
// the stacking order is taken, as the stock default action does. null when there is none.
function activeTaskPath(tasks)
{
    for (let row = 0; row < tasks.length; ++row) {
        const task = tasks[row];
        if (!task.active) {
            continue;
        }
        if (task.children.length === 0) {
            return [row];
        }
        let best = -1;
        let highest = -Infinity;
        for (let child = 0; child < task.children.length; ++child) {
            const window = task.children[child];
            if (window.active && window.stacking >= highest) {
                highest = window.stacking;
                best = child;
            }
        }
        return best === -1 ? null : [row, best];
    }
    return null;
}

// Whether ITEM, the item that has the keyboard focus, is the reply field of a notification or is
// inside it (its send button): the banner's Escape is then not its own. The parents are walked
// up to CONTENT, the banner's content, which is never the field itself. On this Qt a plain
// parent's activeFocus does not follow a descendant's, so the focus item itself is the source.
function inReplyField(item, content)
{
    for (let node = item; node && node !== content; node = node.parent) {
        if (node.isReplyField === true) {
            return true;
        }
    }
    return false;
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

// "dismiss" while the interaction is active, unless the keyboard focus is in the reply field: there
// Escape keeps its stock behaviour, so a draft is not lost. From any other control of the banner,
// a button included, it dismisses. The expiry runs once per interaction, since the banner is on its
// way out after the first, and never on a held key; "consume" is such a key. "" when the key is
// not ours.
function escapeAction(interactionActive, replyFieldFocused, dismissed, autoRepeat)
{
    if (!interactionActive || replyFieldFocused) {
        return "";
    }
    return autoRepeat || dismissed ? "consume" : "dismiss";
}

// "activate" runs the default action on every press that is not the repeat of a held key, and only
// while the banner's content itself has the keyboard focus. A control inside the banner that has
// it (a button, the reply field) acts on the key itself, and the event is not ours. Without a
// default action the key does nothing ("consume"). "" when the key is not ours.
function enterAction(interactionActive, focusOnContent, hasDefaultAction, autoRepeat)
{
    if (!interactionActive || !focusOnContent) {
        return "";
    }
    return autoRepeat || !hasDefaultAction ? "consume" : "activate";
}
