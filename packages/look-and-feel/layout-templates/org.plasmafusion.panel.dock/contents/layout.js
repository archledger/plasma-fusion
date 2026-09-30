/*
    "Add Panel > Plasma Fusion Dock": the dock as the Global Theme's layout script builds it: a
    floating, fit-content, centred bar at the bottom edge, 88 px thick (72 px of dock plus 16 px of
    headroom for magnified icons), hidden over windows. The centred launcher goes with it (no button
    of its own next to the Fusion dock).

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
var known = knownWidgetTypes;
function add(container, candidates) {
    for (var i = 0; i < candidates.length; ++i) {
        if (known.indexOf(candidates[i]) !== -1) {
            var widget = container.addWidget(candidates[i]);
            if (widget && typeof widget === "object" && widget.type !== undefined) {
                return widget;
            }
        }
    }
    return null;
}
var panel = new Panel;
panel.location = "bottom";
panel.height = 88;
panel.floating = true;
panel.lengthMode = "fit";
panel.alignment = "center";
panel.hiding = "dodgewindows";
panel.opacity = "translucent";
var hasLauncherPanel = false;
for (var p = 0; p < panelIds.length; ++p) {
    var other = panelById(panelIds[p]);
    if (other && other.id !== panel.id && other.widgets("org.plasmafusion.launcher").length > 0) {
        hasLauncherPanel = true;
    }
}
if (!hasLauncherPanel && known.indexOf("org.plasmafusion.dock") !== -1) {
    var launcher = add(panel, ["org.plasmafusion.launcher"]);
    if (launcher) {
        launcher.currentConfigGroup = ["General"];
        launcher.writeConfig("buttonStyle", "hidden");
        launcher.currentConfigGroup = [];
    }
}
if (!add(panel, ["org.plasmafusion.dock"])) {
    add(panel, ["org.kde.plasma.icontasks", "org.kde.plasma.taskmanager"]);
}
