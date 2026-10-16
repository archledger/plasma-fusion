# Quick Look: `plasma-fusion-quicklook` (Space in Dolphin)

Status: new in the release after 0.5.0 (queue item 5 of the 2026-10-14 feature report, owner's
choice of 2026-10-15: Plasma Fusion's own previewer, Space in Dolphin opens it). Package
`plasma-fusion-quicklook` (the fourth compiled part). Last edited 2026-10-15.

## What it is

macOS's Quick Look (spacebar preview; bugs.kde.org 272539, "Instant preview like OSX", 8
duplicates): select files in Dolphin, press Space, and a window shows what is in them without
opening them.

| Kind (`QuickLookItem::kind`) | How it is decided | Viewer |
|---|---|---|
| `image`, `animation` | an `image/*` type (or one a Qt image plugin reads, Krita's for one) that `QImageReader` can read; more than one frame: `animation` | `ImageViewer.qml`: centred, scaled down to fit, never up, decoded at the shown size; GIF/WebP animations play |
| `pdf` | `application/pdf` | `PdfViewer.qml`: Qt PDF (PDFium), the pages one under the other at the window's width, fitted again when the window is resized until the user zooms (a pinch) |
| `text` | inherits `text/plain` and has no NUL byte in its first 8 KiB | `TextViewer.qml`: fixed-width font, KSyntaxHighlighting colours for the file name's language (dark or light theme by the window's colours), the first 512 KiB (ending at a line break; one longer line ends before the character the limit cut) with a note when cut; UTF-8, else Latin-1 |
| `audio`, `video` | `audio/*`, `video/*` | `MediaViewer.qml`: Qt Multimedia, plays at once; a song shows its cover (KIO's thumbnail) or icon; play/pause and the position |
| `folder` | a directory | `FolderViewer.qml`: icon and name; the details give the items in it and KIO's size of everything below |
| `file` | anything else | `FileViewer.qml`: KIO's thumbnail (the thumbnailers Dolphin uses: documents, fonts, comics...) or the type's icon, the name and type; also in place of a viewer whose Qt module is missing (a PDF without Qt PDF), asking KIO for the thumbnail then |
| `missing` | gone since it was selected | `FileViewer.qml`: "This file is no longer there" |

The window's title is the file's name ("beta.txt (2 of 5) — Quick Look" with several files).
Above the viewer: previous/next (several files), "2 of 5", the name, **Open with <application>**
(the type's preferred application, `KIO::OpenUrlJob`; the window closes once it is started), Close.
Below: the type, the image size, the size, the modified time, and the viewer's own facts (pages,
lines, the length of a song).

Keys: Space or Esc closes, Left/Up and Right/Down go through the files (round), Enter opens the
shown one, Ctrl+C copies the text selected in the text view. The keyboard stays with the window:
the text area takes no focus (the mouse still selects text, and the window's Copy key copies it).

The thumbnails KIO made are kept while their file is in the preview (`Thumbnails`, the image
provider's store) and dropped with it, when another selection replaces it.

One preview at a time (`KDBusService::Unique`): a second start hands its files to the first, and
the same files again close it, so Space on the same selection in Dolphin closes the preview as in
macOS; another selection replaces it and the window comes to the front with the second start's
activation token. Local files only (`X-KDE-Protocols=file`; remote ones are left out, as Dolphin's
own maintainers want for now, see "Upstream").

The window is a Qt Quick Controls window in the desktop style (`org.kde.desktop`) with Kirigami:
it has the colours, fonts and window decoration every KDE application has under Plasma Fusion and
draws nothing of its own (no board has a preview window; nothing beyond the system style is used).

## Starting it

- **Context menus:** `plasma-fusion-quicklook.desktop` in `kio/servicemenus` adds "Quick Look"
  (`document-preview`) for every local file and folder (`MimeType=all/all`) to the context menus of
  Dolphin and the desktop.
- **Space in Dolphin:** Dolphin 26.04 and later (commit db49ac4e, KIO 6.24
  `KFileItemActions::createServiceMenuActions()`) list every service-menu action among Dolphin's
  shortcuts ("Context Menu Actions"), this one as
  `servicemenu_plasma-fusion-quicklook.desktop::quicklook`. Dolphin gives a window shortcut on Space
  the key while its view has focus and no type-ahead search runs (`handleSpaceAsNormalKey`). Its own
  default for Space is "Select Files and Folders" (`toggle_selection_mode`); two actions on Space
  would be ambiguous and neither would run. The setup (`tools/device/fusion-config.sh`,
  `ensure_quicklook_space`, docs/parts/device.md) therefore gives Space to Quick Look and takes it
  from selection mode, which keeps its toolbar button and menu entry. With nothing selected Space
  does nothing (KIO runs a service-menu shortcut only on a selection; Dolphin MR !1470 would toggle
  selection mode there, which a service menu cannot). Dolphin starts with its first file current
  but not selected: a click (or a key that moves the current file) selects one. Fedora 44 (Dolphin 26.08.1,
  KIO 6.31), Arch (26.08.2), Debian testing (26.08.0, KIO 6.30) and Ubuntu 26.10 (26.08.1, KIO 6.29)
  all have it (2026-10-15).
- From a terminal: `plasma-fusion-quicklook FILE...`.

## Upstream

Dolphin MR !1470 (open, "Wait-for-stable-branching") sends Space on a selected file to Kiview, a
preview program over D-Bus; Dolphin's maintainers will merge it only once Kiview is a KDE
application in Gear (2026-10-01/02), and Kiview (GPL-3.0-or-later) is not packaged by the
distributions. Two in-Dolphin previews (!1455, !1209) were closed. When Dolphin has a Space preview
of its own, the setup should stop taking Space from selection mode (not done yet: Dolphin has none
on 2026-10-15).

## Files

| File | What |
|---|---|
| `packages/quicklook-cpp/CMakeLists.txt`, `src/CMakeLists.txt` | ECM project: `quicklookcore` (static library: the model, shared with the model test), the program with its QML compiled in (`qt_add_qml_module`, `org.plasmafusion.quicklook`), the two desktop files, `built-against/quicklook` |
| `src/quicklook.h`, `src/quicklook.cpp` | `QuickLookItem` (the kind, the facts, the text, the folder size, the thumbnail, the application) and `QuickLookSession` (the files, the shown one, a second Space, opening, the test report) |
| `src/thumbnails.h`, `src/thumbnails.cpp` | the thumbnails KIO made, `image://quicklook-thumbnail/<id>` |
| `src/main.cpp` | command line, the single instance and its activation, the window |
| `src/qml/*.qml` | the window and the six viewers |
| `data/org.plasmafusion.quicklook.desktop` | the window's name and icon (its Wayland application id), not in the menus |
| `data/plasma-fusion-quicklook.desktop` | the service menu |
| `tests/quicklooktest.cpp` | `quicklook-model` (QTest) |
| `tests/run-viewers.sh` | `quicklook-viewers`: the program offscreen on sample files of every kind |

## Build

```
cmake -S packages/quicklook-cpp -B build/quicklook -G Ninja -DBUILD_TESTING=ON
cmake --build build/quicklook
QT_QPA_PLATFORM=offscreen ctest --test-dir build/quicklook --output-on-failure
```

Needs Qt 6.8 (Core, Gui, Widgets, Qml, Quick, QuickControls2) and KDE Frameworks 6.10 (CoreAddons,
DBusAddons, I18n, KIO, Service, WindowSystem); at run time the QML modules of Kirigami, the desktop
style, Qt PDF, Qt Multimedia and KSyntaxHighlighting. Packages: Fedora `plasma-fusion-quicklook`
(Requires those modules, Recommends kio-extras, kf6-kimageformats, qt6-qtimageformats, qt6-qtsvg,
dolphin; the spec gives its QML a time stamp derived from its sources, as the settings page's,
docs/parts/system.md); Debian `plasma-fusion-quicklook` (the qml6-module-* packages; KDE neon has
the desktop style's module in `kf6-qqc2-desktop-style`, the alternative it depends on there); Arch
`plasma-fusion-quicklook` (Qt PDF comes with qt6-webengine there, so it is optional: without it a
PDF shows its thumbnail, the viewer's loader falling back); Nix `plasma-fusion-quicklook` (wrapped
with its QML modules). The main package recommends it (Arch: optdepends).

## Tests

- `quicklook-model` (`tests/quicklooktest.cpp`, ctest; CI `compiled` and `sanitizers`; 23 QTest
  results, all pass): every kind
  (PNG, SVG, text, Python, JSON, a `.txt` holding a NUL, PDF, WAV, MP4, ZIP, a folder), the image
  size in the details, UTF-8 and Latin-1 text, the 512 KiB limit ending at a line break, one longer
  line cut inside a UTF-8 character (still UTF-8, the cut character left out, no replacement
  character: `QStringDecoder` is stateful and keeps an unfinished character as its state), a
  folder's 3 items and KIO's 9 B in all, a missing file, the session (a second Space on the same
  files, next/previous round, another selection, relative paths and file: URLs, remote ones left
  out), a text file's thumbnail asked for once by the file view and dropped from the store with
  the next selection (skipped without kio-extras' text thumbnailer).
- `quicklook-viewers` (`tests/run-viewers.sh`, ctest with dbus-run-session; 30 checks, all pass):
  the program offscreen with `--test-report` shows eleven samples in turn and reports what each
  viewer showed, again in a window 240 px wider and, for the PDF, after a zoom and the window
  narrowed back: the PNG at 64 x 48, a two-frame GIF playing, the SVG drawn, the text's length and
  its 2 lines, the text view's selection copied to the clipboard, Python highlighting, the PDF's one
  page ("1 page") as wide as the window when shown and after the resize (560 and 800 px) and a zoom
  kept when the window narrows, the WAV's 1000 ms, the folder's "3 items", the ZIP in the file view,
  an OpenDocument text's thumbnail of its first page (KIO, from kio-extras), the missing file; a
  second run with `--test-unavailable text` (the text viewer taken as missing) shows the text file's
  KIO thumbnail in the file view. CI installs the run-time modules from the line in
  `tests/CMakeLists.txt`.
- Both pass with `-Werror` and under AddressSanitizer and UndefinedBehaviorSanitizer with leak
  detection (`tools/sanitizers/run.sh`); `packaging/build-rpm.sh --compiled` builds the package
  with rpmlint at 0 errors (Fedora 44 container, 2026-10-15).
- The setup's step: `tools/device/tests/quicklook-keys-unit.sh` (CI `build`, docs/parts/device.md).
- `tests/vsession/scenario-quicklook.sh`: real Dolphin in a private session (KWin's emulated keys),
  Quick Look installed below `~/.local` (a service menu there needs the executable bit, as KIO asks
  of service menus outside the system directories; the packages install below `/usr/share`). It
  quits only its own session's Dolphin (by the session's private `XDG_RUNTIME_DIR`): the test host's
  desktop runs under the same user, and a stand-in Dolphin with another runtime directory is
  checked to survive the cleanup (2026-10-16, 14 checks pass on the test laptop).
  2026-10-15, Fedora 44 VM (Dolphin 26.08.1, KF 6.30, Qt 6.11.2, KWin 6.7.5), 1440x900: 12 checks
  pass - the setup's file of version 0; after Dolphin's start its own interface (version 49, menus
  and toolbars) with the two keys; one selected file: Space opens "alpha.png — Quick Look", Space
  closes it and the program ends; Ctrl+A: "(1 of 3)", Right "(2 of 3)", "(3 of 3)", Esc closes; Space
  again in Dolphin on the same files closes the preview; `fusion-restore.sh` removes the file and
  Space opens nothing after Dolphin starts again. Red runs: no setup (Dolphin's own keys) and Space
  on both actions (ambiguous): Space opens nothing. Screenshots in the evidence folder.
  2026-10-15, review round 1, private sessions on the Fedora 44 test laptop (the same versions),
  1440x900: 13 checks pass, the new one: the text file's two lines selected with a mouse drag in
  the Quick Look window and Ctrl+C put them on the clipboard (`wl-paste`). `~/ql-mode` "removed":
  after Quick Look is removed and the setup runs again, Dolphin's file keeps its own interface
  without the two entries and Space opens selection mode (Dolphin's view changes, its selection
  bars in the screenshot). Red runs: "removed-red" (no second setup: the entries stay, Space does
  nothing) and a program without the Copy shortcut (the text selected, the clipboard empty).
- Red runs of the unit suites: eight single changes (no binary check, no second-Space check, no
  line-end cut, no Latin-1, no animation, remote files kept, no 512 KiB limit, lines counted by the
  text area) each fail their check; five of the setup step's rules undone each fail
  `quicklook-keys-unit.sh`. Review round 1 (2026-10-15): a stateless UTF-8 decoding
  (`QString::fromUtf8`), thumbnails not dropped, a text file asking for a thumbnail, no thumbnail
  for the file view in place of a viewer, the PDF fitted before Qt's page view sets its scale back
  to 1 for a new document (`PdfMultiPageView` does so when the source changes: the page stayed at
  scale 1), no fit on resize, a fit on resize after a zoom, and no copy each fail their check; the
  setup without the undo once Quick Look is gone, and the undo without its mark, each fail
  `quicklook-keys-unit.sh`.
