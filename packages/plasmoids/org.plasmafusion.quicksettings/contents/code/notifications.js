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
