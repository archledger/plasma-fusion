# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# The launcher's sections in a private session (real plasmashell and KWin): the Fusion setup with
# the stage in ~/pf-stage and tools/ in ~/pf-tools, then the launcher (hidden next to the Fusion
# dock) opened with openRequest and its chips read from its frames report ("launcher: frames ...,
# chips all+recentapps+places+..."), as the settings page's Launcher switches change its keys:
#   1. the defaults: All, Recent and Places;
#   2. showRecentApps off: no Recent chip; showPlaces off: no Places chip either;
#   3. both on again: both back;
#   4. showRecommended off: the home view without the recent files (screenshots).
# Run: tools/vsession/remote.sh launcher-sections packages/plasmoids/org.plasmafusion.launcher/tests/vsession/scenario-sections.sh SEED 1440x900 240
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
PLOG=$OUT/plasmashell.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
# A step that fails stops the scenario (strict mode); the reason lands in the checks.
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
launcher_js() { # BODY: run BODY for every launcher widget (w), General group
  evaljs - <<JS
panels().forEach(function (p) { p.widgets("org.plasmafusion.launcher").forEach(function (w) { w.currentConfigGroup = ["General"]; $1 }); });
JS
}
# The chips of the launcher's last frames report, after asking for one (none: empty, which the
# check after it reports).
chips() {
  launcher_js "w.writeConfig(\"openRequest\", \"frames:\" + Date.now());" >/dev/null 2>>"$OUT/errors.log"
  sleep 1
  { grep -a "launcher: frames" "$PLOG" || true; } | tail -1 | sed -n 's/.*, chips //p'
}
open_home() { launcher_js "w.writeConfig(\"openRequest\", \"home:\" + Date.now());" >/dev/null 2>>"$OUT/errors.log"; sleep 1.5; }

fc=0
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || fc=$?
info "fusion-config rc=$fc"
[ "$fc" = 0 ]
pfv_restart_shell 12
info "launchers: $(launcher_js 'print(w.type);' 2>>"$OUT/errors.log" | tr '\n' ' ')"

# ---- 1. the defaults
open_home
c=$(chips)
case "+$c+" in
  +all+recentapps+places+*) pass "1: by default the chips start with All, Recent and Places ($c)" ;;
  *) fail "1: the default chips ($c)" ;;
esac
shot 10-default

# ---- 2. Recent off, then Places off
launcher_js 'w.writeConfig("showRecentApps", false);' >/dev/null 2>>"$OUT/errors.log"
sleep 1
c=$(chips)
case "+$c+" in
  +all+places+*) pass "2: Recent off: All, then Places ($c)" ;;
  *) fail "2: Recent off ($c)" ;;
esac
launcher_js 'w.writeConfig("showPlaces", false);' >/dev/null 2>>"$OUT/errors.log"
sleep 1
c=$(chips)
case "+$c+" in
  *+recentapps+*|*+places+*) fail "2: Places off too ($c)" ;;
  +all+*) pass "2: Places off too: neither chip ($c)" ;;
  *) fail "2: Places off too ($c)" ;;
esac
shot 20-chips-off

# ---- 3. both on again
launcher_js 'w.writeConfig("showRecentApps", true); w.writeConfig("showPlaces", true);' >/dev/null 2>>"$OUT/errors.log"
sleep 1
c=$(chips)
case "+$c+" in
  +all+recentapps+places+*) pass "3: both on again: both back ($c)" ;;
  *) fail "3: both on again ($c)" ;;
esac

# ---- 4. the recent files off (the home view, screenshots)
launcher_js 'w.writeConfig("showRecommended", false);' >/dev/null 2>>"$OUT/errors.log"
open_home
shot 40-no-recent-files
launcher_js 'w.writeConfig("showRecommended", true);' >/dev/null 2>>"$OUT/errors.log"
open_home
shot 41-recent-files
{ grep -a "launcher.*rror\|launcher.*TypeError" "$PLOG" || true; } | head -5 | sed 's/^/INFO log: /' >>"$CHK"
info "done"
# A failed check fails the scenario (scenario rc), as the KWin scenarios do.
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$CHK" || true)" = 0 ]
