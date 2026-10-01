/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

// Stroke glyphs from the design boards (24x24 grid, 1.8 stroke, round caps and joins).
const glyphs = {
    search: "M4 11a7 7 0 1 0 14 0a7 7 0 1 0-14 0M20 20l-4-4",
    meta: "M5 5h14v14H5zM9 9h6v6H9z",
    chevronRight: "M9 6l6 6-6 6",
    chevronLeft: "M15 6l-6 6 6 6",
    clear: "M7 7l10 10M17 7L7 17",
    lock: "M7 11h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2zM8 11V8a4 4 0 0 1 8 0v3",
    sleep: "M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z",
    restart: "M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5",
    power: "M12 3v9M6.3 6.3a8 8 0 1 0 11.4 0",
    doc: "M7 3h7l5 5v13H7zM14 3v5h5M10 13h6M10 17h4",
    image: "M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM7 10a2 2 0 1 0 4 0a2 2 0 1 0-4 0M21 15l-5-5-10 10",
    sheet: "M4 5h16v14H4zM4 10h16M4 15h16M10 5v14",
    code: "M9 8l-4 4 4 4M15 8l4 4-4 4",
    slides: "M4 5h16v11H4zM12 16v4M8 20h8",
    music: "M9 18V6l10-2v12M5 18a2 2 0 1 0 4 0a2 2 0 1 0-4 0M15 16a2 2 0 1 0 4 0a2 2 0 1 0-4 0",
    video: "M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zM10 9l5 3-5 3z",
    archive: "M4 8h16v12H4zM3 4h18v4H3zM10 12h4",
    folder: "M3 7.5A2 2 0 0 1 5 5.5h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z",
    pin: "M9 4h6M10 4v5l-3 4h10l-3-4V4M12 13v7",
    more: "M6 12h.01M12 12h.01M18 12h.01",
};

// Recent-file tiles: colour and glyph per kind (colours from the design palette).
const fileKinds = {
    doc: { color: "#2f6fdf", glyph: "doc" },
    sheet: { color: "#1f9e8f", glyph: "sheet" },
    slides: { color: "#e8743b", glyph: "slides" },
    pdf: { color: "#d9434b", glyph: "doc" },
    image: { color: "#3aa65b", glyph: "image" },
    audio: { color: "#d6457a", glyph: "music" },
    video: { color: "#c2410c", glyph: "video" },
    code: { color: "#7b5cd6", glyph: "code" },
    archive: { color: "#a8741a", glyph: "archive" },
    folder: { color: "#3f7fe0", glyph: "folder" },
    other: { color: "#5b6478", glyph: "doc" },
};

const extensionKinds = {
    odt: "doc", ott: "doc", doc: "doc", docx: "doc", rtf: "doc", txt: "doc", md: "doc", tex: "doc", pages: "doc", fodt: "doc",
    ods: "sheet", ots: "sheet", xls: "sheet", xlsx: "sheet", csv: "sheet", tsv: "sheet", fods: "sheet", numbers: "sheet",
    odp: "slides", otp: "slides", ppt: "slides", pptx: "slides", key: "slides", fodp: "slides",
    pdf: "pdf", epub: "pdf", djvu: "pdf", xps: "pdf",
    png: "image", jpg: "image", jpeg: "image", gif: "image", webp: "image", svg: "image", svgz: "image", bmp: "image",
    tif: "image", tiff: "image", heic: "image", heif: "image", avif: "image", jxl: "image", kra: "image", xcf: "image", psd: "image",
    mp3: "audio", flac: "audio", ogg: "audio", oga: "audio", opus: "audio", wav: "audio", m4a: "audio", aac: "audio",
    mp4: "video", mkv: "video", webm: "video", mov: "video", avi: "video", m4v: "video", ogv: "video",
    qml: "code", js: "code", mjs: "code", ts: "code", py: "code", c: "code", cc: "code", cpp: "code", cxx: "code", h: "code",
    hpp: "code", rs: "code", go: "code", java: "code", kt: "code", sh: "code", bash: "code", fish: "code", json: "code",
    xml: "code", html: "code", htm: "code", css: "code", scss: "code", yml: "code", yaml: "code", toml: "code", ini: "code",
    rb: "code", php: "code", lua: "code", cmake: "code", desktop: "code", patch: "code", diff: "code",
    zip: "archive", tar: "archive", gz: "archive", tgz: "archive", xz: "archive", zst: "archive", bz2: "archive",
    "7z": "archive", rar: "archive", iso: "archive", rpm: "archive", deb: "archive",
};

function fileKind(name, url) {
    const source = String(name || url || "");
    const dot = source.lastIndexOf(".");
    const ext = dot >= 0 ? source.slice(dot + 1).toLowerCase() : "";
    const kind = extensionKinds[ext] || "other";
    return fileKinds[kind];
}

// Short design names for the pinned tiles of the default apps (Launcher board).
const designLabels = {
    "org.kde.dolphin.desktop": "Files", "org.gnome.Nautilus.desktop": "Files",
    "preferred://browser": "Browser",
    "org.kde.konsole.desktop": "Terminal", "org.gnome.Ptyxis.desktop": "Terminal",
    "org.kde.kmail2.desktop": "Mail", "org.kde.kontact.desktop": "Mail", "org.mozilla.Thunderbird.desktop": "Mail", "org.gnome.Evolution.desktop": "Mail",
    "org.kde.kate.desktop": "Code", "org.kde.kdevelop.desktop": "Code", "code.desktop": "Code", "codium.desktop": "Code",
    "org.kde.kwrite.desktop": "Code", "org.gnome.TextEditor.desktop": "Code",
    "org.kde.elisa.desktop": "Music", "org.gnome.Decibels.desktop": "Music",
    "org.kde.gwenview.desktop": "Photos", "org.kde.koko.desktop": "Photos", "org.gnome.Loupe.desktop": "Photos",
    "systemsettings.desktop": "Settings",
    "org.kde.korganizer.desktop": "Calendar", "org.kde.merkuro.calendar.desktop": "Calendar", "org.gnome.Calendar.desktop": "Calendar",
    "org.kde.marknote.desktop": "Notes", "org.kde.knotes.desktop": "Notes",
    "org.kde.kcalc.desktop": "Calculator", "org.kde.kalk.desktop": "Calculator", "org.gnome.Calculator.desktop": "Calculator",
    "org.kde.discover.desktop": "Software", "org.gnome.Software.desktop": "Software",
    "org.kde.haruna.desktop": "Videos", "org.kde.dragonplayer.desktop": "Videos", "vlc.desktop": "Videos",
    "org.gnome.Showtime.desktop": "Videos",
    "org.kde.neochat.desktop": "Chat",
    "org.kde.marble.desktop": "Maps", "org.gnome.Maps.desktop": "Maps",
    "org.kde.kweather.desktop": "Weather", "org.gnome.Weather.desktop": "Weather",
    "org.kde.plasma-systemmonitor.desktop": "Monitor", "org.gnome.SystemMonitor.desktop": "Monitor",
    "org.kde.spectacle.desktop": "Screenshot",
};

// Category chips: key from the XDG menu directory icon (locale independent), then the design order.
const categoryOrder = ["development", "graphics", "internet", "multimedia", "office", "system",
                       "games", "education", "science", "utilities", "settings", "help"];

function categoryKey(icon, label) {
    let name = String(icon || "").replace(/-symbolic$/, "");
    const byIcon = {
        "applications-development": "development",
        "applications-graphics": "graphics",
        "applications-internet": "internet",
        "applications-network": "internet",
        "applications-multimedia": "multimedia",
        "applications-office": "office",
        "applications-system": "system",
        "applications-games": "games",
        "applications-education": "education",
        "applications-science": "science",
        "applications-utilities": "utilities",
        "applications-accessories": "utilities",
        "preferences-system": "settings",
        "preferences-desktop": "settings",
        "help-about": "help",
        "help-browser": "help",
        "applications-other": "other",
    };
    if (byIcon[name]) {
        return byIcon[name];
    }
    const text = String(label || "").toLowerCase();
    for (const key of categoryOrder) {
        if (text.indexOf(key) === 0) {
            return key;
        }
    }
    return text.length > 0 ? "x-" + text : "";
}

function categoryRank(key) {
    const i = categoryOrder.indexOf(key);
    return i >= 0 ? i : categoryOrder.length;
}

// Text of a key press that should go to the search field: printable characters only
// (Escape, Backspace, Delete and other control keys carry control characters as text).
function isPrintable(text) {
    return String(text || "").length > 0 && !/[\u0000-\u001f\u007f]/.test(text) && text.trim().length > 0;
}

// Splits the configured default pins into slots of alternatives.
function pinnedSlots(entries) {
    const slots = [];
    for (const entry of entries || []) {
        const ids = String(entry).split("|").map(s => s.trim()).filter(s => s.length > 0);
        if (ids.length > 0) {
            slots.push(ids);
        }
    }
    return slots;
}

// The search's runners (S10, decision 6): apps first, then settings, files, calculators and the
// session; no runner that reaches the network or starts a service (web shortcuts, bookmarks,
// browser history and tabs, dictionary, software centre, contacts, spell checking).
const searchRunners = [
    "krunner_services", "krunner_systemsettings", "baloosearch", "krunner_recentdocuments",
    "krunner_placesrunner", "calculator", "unitconverter", "org.kde.datetime", "windows",
    "krunner_sessions", "krunner_powerdevil", "krunner_shell", "locations", "krunner_kill",
    "krunner_charrunner", "krunner_katesessions", "krunner_konsoleprofiles",
];

// An app id without the "applications:" scheme: Plasma 6.8's Kicker gives application entries
// "applications:org.kde.dolphin.desktop" where 6.7 gave "org.kde.dolphin.desktop" (pinned entries
// always had the scheme), while the configured pins and design labels use the plain desktop id.
function appId(id) {
    return String(id || "").replace(/^applications:/, "");
}

// The icon theme name of an app entry (its desktop file name), for FusionIconTile's coverage
// check: "applications:org.kde.dolphin.desktop" -> "org.kde.dolphin".
function iconNameFor(entry) {
    const id = entry && entry.favoriteId ? String(entry.favoriteId) : "";
    if (id === "" || id.indexOf("://") >= 0) {
        return "";
    }
    return id.replace(/^applications:/, "").replace(/\.desktop$/, "");
}
