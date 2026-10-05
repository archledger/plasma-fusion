<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: GPL-2.0-or-later
-->

# App consistency: keeping foreign toolkits in the Plasma Fusion look

Status: written 2026-10-05 from the settings survey
(`artifacts/plasma-fusion/2026-10-05-de-ux-survey/report.md`, § 5). The reference kits are
generated from the shipped colour schemes; the app table grows one row per app as it is checked.

Plasma Fusion feeds the standard appearance channels, so anything that follows the desktop is
already in the look: the XDG settings portal (`org.freedesktop.appearance` `color-scheme`,
`accent-color`, `contrast`, `reduced-motion`; verified end to end by
`tools/tests/settings/portal-audit.sh`), the GTK settings (`kde-gtk-config`, set up by
`fusion-config.sh`) and the Qt platform theme. Everything else needs app-side work; this page
holds the map and the values to give app authors.

## Toolkit matrix

| Toolkit | How it gets themed | Follows dark | Follows accent | What Plasma Fusion does |
|---|---|---|---|---|
| Qt 6 / QML (KDE apps) | Qt platform theme, KStyle/Breeze, colour schemes, the decoration | yes | yes | native: the Global Themes, colour schemes, fonts and `org.plasmafusion.decoration` |
| GTK 3 | `breeze-gtk` + `kde-gtk-config` (System Settings > Application Style > GTK) | yes, once configured (some builds need the gtk settings service restarted) | no (GTK 3 has no accent API) | `fusion-config.sh` writes the GTK colours and the Fusion stylesheet |
| GTK 4 / libadwaita | the portal keys; `Adw.StyleManager` (PREFER/FORCE light/dark) | yes, by default | app-dependent; the portal `accent-color` is the standard route | the Global Theme keeps the portal keys correct |
| Electron | Chromium's native theme: GTK settings and the portal (Chromium 114+); `nativeTheme.themeSource`; app CSS for the rest | yes when the app uses `nativeTheme` (apps reading `prefers-color-scheme` directly misbehave) | no (app CSS) | the values below for app authors |
| Tauri | WebKitGTK webview + app CSS | unreliable: upstream issue 9427 (`tauri://theme-changed` always light on Linux) | no | the values below; track the upstream fix |
| Flutter (GTK embedder) | GTK embedder for the shell, app-rendered Material for the content | only where the app maps `platformBrightness` | no | `flutter_fusion.dart` |
| wxWidgets (wxGTK) | the GTK theme | follows the theme; `wxSystemSettings::GetColour` cannot tell light from dark on GTK (forum, 2026-08); newer wx has `wxApp::SetAppearance` / `GetAppearance().AreAppsDark()` | no | `wx_fusion.md`; with the GTK values installed the apps look right even though their detection API is weak |
| Dear ImGui | nothing: the app sets `ImGuiStyle` and loads its own fonts | never automatic | never automatic | `imgui_fusion.cpp` |
| Java (Swing/JavaFX) | the GTK or system LAF | yes via the GTK LAF | no | covered by the GTK values |
| FLTK | the GTK2/Pango backends | yes | no | covered by the GTK values |
| Avalonia, .NET MAUI, custom Skia UIs | app-level themes | only where the app implements it | no | the CSS/colour values as a reference |
| SDL, Unity, Godot games | their own UIs (usually fullscreen) | n/a | n/a | cursor and colour scheme in windowed modes |

## App table

Fill one row per app after checking it against Plasma Fusion Dark and Light. "Dark follows" means
the app switches with the system `color-scheme` portal key without an in-app setting. The first
four rows were checked 2026-10-05 in the ubuntu2610 VM (Fusion Dark and Light applied per app,
screenshots in `artifacts/plasma-fusion/2026-10-05-settings-plan/app-consistency/`): the verdict
for dark follows compares the app window's pixels across the two themes, and the title bar and
file dialog columns are what the toolkit draws.

| App | Toolkit | Dark follows | Accent follows | Title bars | File dialog | Notes |
|---|---|---|---|---|---|---|
| LibreOffice | Qt 6 (`libreoffice-qt6` VCL) | yes (chrome changes with the theme) | yes (scheme colours) | SSD | KDE dialog (KIO) | VM-checked 2026-10-05 |
| GIMP 3 | GTK 3 | no (its own theme: the window is identical under Fusion Dark and Light) | no | CSD | own (GtkFileChooser) | VM-checked 2026-10-05 |
| Inkscape | GTK 3 | no (identical under both) | no | CSD | own (GtkFileChooser) | VM-checked 2026-10-05 |
| VS Code | Electron | no (its own dark theme; "auto detect color scheme" is opt-in) | no | CSD | own | VM-checked 2026-10-05 |
| Discord | Electron | app setting | no | CSD | app dialog | not yet checked on Plasma Fusion |
| Spotify | Electron | app setting | no | CSD | app dialog | not yet checked on Plasma Fusion |
| Obsidian | Electron | broken unless the app uses `nativeTheme` | no | CSD | app dialog | the "adapt to system" case from the survey |
| Steam | custom Chromium | no (own skin) | no | CSD | own dialog | games themselves are out of scope |
| Blender | custom OpenGL | no (own theme) | no | SSD | own dialog | match with `imgui_fusion`-style values if it matters |

## Reference kits

Generated by `packages/color-schemes/export-kits.py` from `PlasmaFusionDark.colors` and
`PlasmaFusionLight.colors`; checked by `packages/color-schemes/tests/check-kits.py`. Regenerate
after any scheme change and commit the output.

- `reference-kits/fusion-{dark,light}.css`: CSS custom properties for webviews and web content.

  ```css
  :root {
    --fusion-accent: #2f6fdf;
    --fusion-bg: #1f2540;
    /* ... */
  }
  ```

- `reference-kits/imgui_fusion.cpp`: Dear ImGui colour assignments.

  ```cpp
  #include "imgui_fusion.cpp"  // or copy the functions
  ApplyFusionDark(ImGui::GetStyle());
  ```

- `reference-kits/flutter_fusion.dart`: Flutter `ColorScheme` constants.

  ```dart
  MaterialApp(theme: ThemeData(colorScheme: fusionDark))
  ```

- `reference-kits/wx_fusion.md`: wxWidgets `wxSystemColour` roles per scheme.

A scheme's accent is its `Colors:Selection` BackgroundNormal (what the portal reports as
`accent-color`); the schemes carry no separate `AccentColor` key.

## Title bars

The Plasma Fusion title bars (`org.plasmafusion.decoration`, the shadow-only "Only shadow" rule)
apply to windows that let the system draw the frame. GTK 3/4 and most Electron apps draw their
own header bars (CSD); the supported lever is `gtk-decoration-layout` (ArchWiki: "Add Title bar
and frame to GTK3 applications under KDE Plasma"), and some Electron apps offer a custom title
bar toggle. Expect CSD apps to keep their own header bars and match them with the palette above
rather than forcing a frame.

## Checking the kits

```sh
python3 packages/color-schemes/export-kits.py      # regenerate
python3 packages/color-schemes/tests/check-kits.py # must print "check-kits: ok"
```
