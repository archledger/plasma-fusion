.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    What a notification card of the history shows (NotificationCard.qml), following Plasma 6.7's
    Notifications applet (applets/notifications/components). Tests: tests/notifications.test.js
    (not installed).
*/

// The body as the server hands it over (sanitised XHTML: an XML declaration and an <html> wrapper
// around b/i/u/a/br/img/table) split into {text, images}: the text for Text.StyledText without
// the declaration (drawn as an empty line) and without the images, and the images' sources, which
// the card draws below the text, fitted to its width. The server keeps the src of local files only
// (and drops it otherwise); an image without a source is left out.
function splitBody(body) {
    var images = [];
    var text = String(body || "")
        .replace(/<\?xml[^>]*\?>/gi, "")
        .replace(/<\/?html>/gi, "")
        .replace(/<img\b[^>]*>(\s*<\/img>)?/gi, function (tag) {
            var src = /\bsrc\s*=\s*("([^"]*)"|'([^']*)')/i.exec(tag);
            var url = src ? (src[2] !== undefined ? src[2] : src[3]) : "";
            if (url !== "") {
                images.push(url.replace(/&amp;/g, "&"));
            }
            return "";
        })
        .replace(/\n/g, "<br>")
        .replace(/^(\s|<br\s*\/?>)+|(\s|<br\s*\/?>)+$/gi, "");
    return { text: text, images: images };
}

// The notification's own image beside the text: the image, or its icon when it is not the app
// icon of the header (the stock applet's Icon.qml); null for none.
function sideImage(image, iconName, applicationIconName) {
    if (image) {
        return image;
    }
    var icon = String(iconName || "");
    return icon !== "" && icon !== String(applicationIconName || "") ? icon : null;
}

// How the card offers an inline reply: "none", "button" (a Reply button first among the actions,
// which opens the field) or "field" (the field right away, when replying is the only action).
function replyMode(hasReply, actionCount) {
    if (!hasReply) {
        return "none";
    }
    return actionCount > 0 ? "button" : "field";
}

// org.kde.notificationmanager enums used below (JobStateRunning is 1).
var JOB_TYPE = 2;
var JOB_STOPPED = 0;
var JOB_SUSPENDED = 2;

// A job's state as the card words it: "running", "paused", "failed", "finished", or "" for a
// notification.
function jobState(type, state, error) {
    if (type !== JOB_TYPE) {
        return "";
    }
    if (state === JOB_SUSPENDED) {
        return "paused";
    }
    if (state === JOB_STOPPED) {
        return error ? "failed" : "finished";
    }
    return "running";
}

// What a finished file job offers ({open, folder, folderUrl, highlight}): the stock applet's
// "Open" and "Open Containing Folder". `destUrl` is the job's effectiveDestUrl: the copied file for
// a single file, the destination folder for several, empty while running, after an error or in
// the trash. One file: Open opens it, the folder button shows it in the file manager (highlight).
// Several: only the folder button, which opens the destination folder.
function fileActions(state, totalFiles, destUrl) {
    var url = String(destUrl || "");
    if (state !== "finished" || url === "") {
        return { open: false, folder: false, folderUrl: "", highlight: false };
    }
    if (totalFiles === 1) {
        return { open: true, folder: true, folderUrl: url, highlight: true };
    }
    return { open: false, folder: true, folderUrl: url, highlight: false };
}

// Whether the summary is worth a line: some apps send their own name as the summary.
function summaryShown(summary, applicationName) {
    var s = String(summary || "").trim().toLocaleLowerCase();
    return s !== "" && s !== String(applicationName || "").trim().toLocaleLowerCase();
}
