# shellcheck shell=bash
# Test scenario for tools/vsession, run with SEED '-' after scenario-full.sh (same HOME, a new
# session = the next login): layout at login, a second dark run (idempotent), a layout reset run
# without a display in the environment (as over SSH), light, the light log-out screen, then
# fusion-restore.sh, also without a display.
# Results in $OUT.
source "$HOME/pf-tools/session-common.sh"
log start
login_shell plasmashell-login.log
kwin_defaults
evaljs "$T/dump-layout.js" >"$OUT/layout-login.txt" 2>&1
shot 00-login-dark
bash "$T/fusion-config.sh" >"$OUT/config-dark-again.log" 2>&1
# Run as over SSH (no display in the environment): the layout is rebuilt and the restarted
# plasmashell takes the environment of the one it replaces.
env -u WAYLAND_DISPLAY -u DISPLAY bash "$T/fusion-config.sh" --reset-layout >"$OUT/config-reset-nodisplay.log" 2>&1
log "reset without display rc=$?"
evaljs "$T/dump-layout.js" >"$OUT/layout-reset-nodisplay.txt" 2>&1
bash "$T/fusion-config.sh" --light >"$OUT/config-light.log" 2>&1
log "light rc=$?"
kwin_defaults
login_shell plasmashell-login-light.log
evaljs "$T/dump-layout.js" >"$OUT/layout-light.txt" 2>&1
shot 20-light
dolphin --new-window "$HOME/.local/share/wallpapers" >/dev/null 2>&1 &
app=$!; sleep 5; shot 21-light-dolphin; kill $app 2>/dev/null
/usr/libexec/ksmserver-logout-greeter --windowed >"$OUT/logout-light.log" 2>&1 &
app=$!; sleep 4; shot 25-logout-light; kill $app 2>/dev/null
bash "$T/fusion-restore.sh" --list >"$OUT/restore-list.txt" 2>&1
env -u WAYLAND_DISPLAY -u DISPLAY bash "$T/fusion-restore.sh" >"$OUT/restore.log" 2>&1
log "restore rc=$?"
sleep 8
shot 30-restored
mkdir -p "$OUT/cfg"
cp -r "$HOME/.config/." "$OUT/cfg/" 2>/dev/null
log end
