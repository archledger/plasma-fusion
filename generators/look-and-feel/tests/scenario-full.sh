# shellcheck shell=bash
# Test scenario for tools/vsession (sourced inside the virtual session; not installed); seed from
# make-seed.sh. Dry run, then fusion-config.sh --install (dark, layout rebuilt), a plasmashell
# restart as at the next login, the log-out screen and the splash. Results in $OUT.
source "$HOME/pf-tools/session-common.sh"
log start
bash "$T/fusion-config.sh" --install "$HOME/pf-stage" --dry-run >"$OUT/config-dry.log" 2>&1
ls "$HOME/.local/state/plasma-fusion" >"$OUT/state-after-dry.txt" 2>&1
bash "$T/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/config-dark.log" 2>&1
log "dark rc=$?"
kwin_defaults
shot 02-dark
evaljs "$T/dump-layout.js" >"$OUT/layout-dark.txt" 2>&1
login_shell plasmashell-login.log
evaljs "$T/dump-layout.js" >"$OUT/layout-dark-login.txt" 2>&1
shot 03-dark-login
dolphin --new-window "$HOME/.local/share/wallpapers" >/dev/null 2>&1 &
app=$!; sleep 5; shot 04-dark-dolphin; kill $app 2>/dev/null
/usr/libexec/ksmserver-logout-greeter --windowed >"$OUT/logout-dark.log" 2>&1 &
app=$!; sleep 4; shot 05-logout-dark; kill $app 2>/dev/null
( ksplashqml --test org.plasmafusion.dark.desktop >"$OUT/ksplash.log" 2>&1 & )
sleep 3.3; shot 10-splash-a; sleep 2.2; shot 11-splash-b; sleep 7
mkdir -p "$OUT/cfg"
cp -r "$HOME/.config/." "$OUT/cfg/" 2>/dev/null
cp "$HOME/.local/state/plasma-fusion/plasmashell.log" "$OUT/plasmashell-restarted.log" 2>/dev/null
log end
