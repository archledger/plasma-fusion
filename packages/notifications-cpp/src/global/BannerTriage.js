/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    The rules of the banner keyboard triage, kept apart from the popup's items so that they can be
    tested: which banner the shortcut takes, which window had the keyboard focus before it, how
    one banner's interaction moves between its states, and what Escape and Enter do on it. The
    applet applies them; KWin decides whether the shortcut is dispatched and which window has focus.

    Each rule is a function of plain values, so that the Qt Test can state them as data: a task of
    the task model arrives as QML reads a model index (valid, row, parent), and a window to return
    to as whatever the applet recorded.
*/

.pragma library

const STATE_IDLE = "idle";
const STATE_REQUESTED = "requested";
const STATE_ACTIVE = "active";

// Whether the shortcut may take a banner: it shows, it is a notification and not a job popup, and
// no reply has been started in it.
function eligible(visible, jobPopup, replyStarted)
{
    return visible && !jobPopup && !replyStarted;
}

// What makes a banner the same notification as before: its id, the time its notification was last
// updated (KDE gives a notification a new update time on every replacement), and what it shows.
// Not its actions: KDE clears them when the application that sent the notification leaves the
// bus, and that is no replacement. It is never reported: what it holds may be private.
function identity(id, updated, summary, body)
{
    return JSON.stringify([id, updated, summary, body]);
}

// Where a task of the task model is, as the model's makePersistentModelIndex takes it: [row] for
// a task of its own, [row of its group, row in the group] for a window inside a group. A task
// arrives as QML reads a model index (valid, row, parent); null when there is none.
function taskCoordinates(task)
{
    if (!task || !task.valid) {
        return null;
    }
    return task.parent && task.parent.valid ? [task.parent.row, task.row] : [task.row];
}

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
// ends a focused interaction in which no reply was started gives the previous window its focus
// back; everything else leaves focus to KWin. With a reply started, the keyboard stays with the
// banner, as it does in stock: typing goes on in the reply field, and nothing may pull it away.
function transition(state, event, replyStarted)
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
        return { state: STATE_IDLE, restoreFocus: state === STATE_ACTIVE && !replyStarted };
    default:
        return { state: state, restoreFocus: false };
    }
}

// The window to record when the shortcut is pressed: the task that has the keyboard focus, unless
// the active window is one of the applet's own taken banners, an older banner taken before this
// one. No task is active then, and the record of the earlier request stands, so that the window
// from before the first press is the one asked for in the end. The record is a window, never a
// banner: when no window has the keyboard focus there is nothing to ask for.
function recordedWindow(takenBannerActive, activeTask, earlierRecord)
{
    return takenBannerActive ? earlierRecord : activeTask;
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
