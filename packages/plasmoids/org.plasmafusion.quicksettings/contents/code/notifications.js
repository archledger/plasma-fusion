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

// The "Show N More" / "Show Fewer" button under the last card of an app's group: {shown, more}.
// `last`: the card is the group's last row in the list. children: the group's notifications;
// expanded: how many of them are listed.
function groupFooter(inGroup, last, children, expanded, isExpanded) {
    var more = Math.max(0, children - expanded);
    return { shown: !!inGroup && !!last && (more > 0 || !!isExpanded), more: more };
}

// The Notification Centre's date beside its clock: the region's long date without the year, in
// the region's order and with its separators ("Sunday, October 11" in en_US, "Sunday 11 October"
// in en_GB, "Sonntag, 11. Oktober" in de_DE), as the lock screen's clock (PfStyle.qml). The year
// goes with a quoted literal just before it ("'de' yyyy") and a CJK year suffix.
function centreDateFormat(longFormat) {
    var f = String(longFormat || "");
    var atEnd = /[\s,.\/-]*('[^']*'\s*)?y+(\s*'[^']*')?[年년]?[\s,.\/-]*$/;
    var atStart = /^y+[年년.\/-]?\s*/;
    var inside = /[\s,]*('[^']*'\s*)?y+(\s*'[^']*')?[年년]?[\s,]*/;
    if (atEnd.test(f)) {
        f = f.replace(atEnd, "");
    } else if (atStart.test(f)) {
        f = f.replace(atStart, "");
    } else {
        f = f.replace(inside, " ");
    }
    f = f.replace(/[\s,]+$/, "").trim();
    return f.length > 0 ? f : "dddd d MMMM";
}

// Where to look for a finished job's result before offering Open and Open Containing Folder, as
// the stock applet's JobItem hides them for a file that does not exist (a cancelled copy, which
// Dolphin reports as finished without an error, or a file moved or deleted since): {folder, filter}
// for a FolderListModel of the parent folder with a name filter that matches exactly that name
// (wildcard characters taken literally); null for a URL that is not a local file (not checked).
function existenceProbe(url) {
    var u = String(url || "").replace(/\/+$/, "");
    if (u.indexOf("file:///") !== 0) {
        return null;
    }
    var slash = u.lastIndexOf("/");
    var name = u.slice(slash + 1);
    if (name === "") {
        return null;
    }
    var filter = decodeURIComponent(name).replace(/[\[\]*?]/g, function (c) {
        return "[" + c + "]";
    });
    return { folder: u.slice(0, slash) || "file:///", filter: filter };
}

// Whether the sheet shows the notification list (PopupContent): on the main page, in the laptop
// layout, while the widget shows notifications (`available`: the setting is on and the service
// loaded), with notifications to list or the empty list asked for (the bell). The clipboard sheet
// (Meta+V, the bar's clipboard button), a page opened on its own (a device plugged in) and the
// tablet posture's controls (the Notification Centre has the list) show none. Closing the sheet
// marks the notifications read only after the list was shown (main.qml), as the stock applet marks
// them read when its pop-up, which is the list, closes.
function listOnSheet(page, apart, available, count, showEmpty) {
    return page === "main" && !apart && available && (count > 0 || showEmpty);
}
