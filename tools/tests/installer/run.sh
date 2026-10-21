#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Tests of scripts/install.sh without changing the machine: fake os-release files, fake package
# managers that only log their calls, and a fake release (file://) whose SHA256SUMS is signed with a
# throwaway key. Every case runs under dash and bash (and busybox sh when podman can run it).
#
#   tools/tests/installer/run.sh [SCRATCH_DIR]
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
INSTALLER=$ROOT/scripts/install.sh
BASE=$(realpath -m "${1:-$ROOT/build/installer-tests}")
rm -rf "$BASE" && mkdir -p "$BASE"
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $*"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $*"; }

# ---------- fakes ----------
LIB=$BASE/lib
mkdir -p "$LIB"
fake() { # NAME BODY: a fake command in the library
  printf '#!/bin/sh\n%s\n' "$2" >"$LIB/$1"
  chmod +x "$LIB/$1"
}
# Each logs "name args" to $FAKE_LOG.
LOGLINE='printf "%s\n" "$(basename "$0") $*" >>"$FAKE_LOG"'
# Package versions come from FAKE_VERSIONS: "name=version ..." (upstream versions).
LOOKUP='v=; for kv in $FAKE_VERSIONS; do [ "${kv%%=*}" = "$1" ] && v=${kv#*=}; done'
fake rpm "$LOGLINE
case \$1 in
  -E) [ -n \"\${FAKE_FEDORA:-}\" ] && echo \"\$FAKE_FEDORA\" || echo %fedora; exit 0 ;;
  -q) fmt=\$3; shift 3
      set -- \"\$1\"; $LOOKUP
      [ -n \"\$v\" ] || { echo \"package \$1 is not installed\"; exit 1; }
      case \$fmt in *RELEASE*) echo \"\$v-1.fc44\" ;; *) echo \"\$v\" ;; esac ;;
esac"
fake pacman "$LOGLINE
[ \"\$1\" = -Q ] || exit 0
set -- \"\$2\"; $LOOKUP
[ -n \"\$v\" ] || { echo \"error: package '\$1' was not found\" >&2; exit 1; }
echo \"\$1 1:\$v-1\""
fake dpkg-query "$LOGLINE
for a; do n=\$a; done; set -- \"\$n\"; $LOOKUP
[ -n \"\$v\" ] || exit 1
echo \"installed 4:\$v-1\""
fake dpkg-deb "$LOGLINE
f=\${2##*/}; f=\${f%_*}; echo \"\${f#*_}\""
fake dpkg "$LOGLINE
[ \"\$1\" = --compare-versions ] || exit 0
[ \"\$2\" = \"\$4\" ] && { [ \"\$3\" = lt ] && exit 1 || exit 0; }
lo=\$(printf '%s\n%s\n' \"\$2\" \"\$4\" | sort -V | head -n 1)
case \$3 in lt) [ \"\$lo\" = \"\$2\" ] ;; gt) [ \"\$lo\" = \"\$4\" ] ;; *) exit 1 ;; esac"
fake nix-store "$LOGLINE
for kv in \$FAKE_VERSIONS; do echo \"/nix/store/0123456789abcdfghijklmnpqrsvwxyz-\${kv%%=*}-\${kv#*=}\"; done"
# The package step "installs" the plasma-fusion command.
INSTALLS='mkdir -p "$FAKE_BIN" && printf "#!/bin/sh\nprintf \"%%s\\\\n\" \"plasma-fusion \$*\" >>\"\$FAKE_LOG\"\n[ \"\$1\" = version ] && echo \"\$FAKE_PF_VERSION\"\nexit \${FAKE_SETUP_RC:-0}\n" >"$FAKE_BIN/plasma-fusion" && chmod +x "$FAKE_BIN/plasma-fusion"'
fake sudo "[ \"\$1\" = -v ] && exit 0
$LOGLINE
exec \"\$@\""
# dnf5 refuses to upgrade a package that is not installed ("Packages for argument 'X' available, but
# not installed.", exit 1; Fedora 44, 2026-10-18).
fake dnf "$LOGLINE
case \" \$* \" in *' install '*) $INSTALLS ;; esac
case \" \$* \" in *' upgrade '*)
  for a; do
    case \$a in -* | upgrade) continue ;; esac
    set -- \"\$a\"; $LOOKUP
    [ -n \"\$v\" ] || { echo \"Packages for argument '\$1' available, but not installed.\" >&2; exit 1; }
  done ;;
esac
exit \${FAKE_DNF_RC:-0}"
# apt-get -s prints what FAKE_APT_SIM holds (apt's simulation lines, "Inst NAME [OLD] (NEW ...)").
fake apt-get "$LOGLINE
case \" \$* \" in *' -s '*) printf '%b' \"\${FAKE_APT_SIM:-}\"; [ -z \"\${FAKE_APT_SIM_ERR:-}\" ] || echo \"\$FAKE_APT_SIM_ERR\" >&2; exit \"\${FAKE_APT_SIM_RC:-0}\" ;; esac
case \" \$* \" in *' install '*) $INSTALLS ;; esac
exit 0"
fake add-apt-repository "$LOGLINE"
fake yay "$LOGLINE
$INSTALLS"
fake makepkg "$LOGLINE
$INSTALLS"
fake busctl "$LOGLINE
[ -n \"\${FAKE_KWIN_RUNNING:-}\" ] && echo \"s \\\"KWin version: \$FAKE_KWIN_RUNNING\\\\nQt Version: 6.11.2\\\"\""
fake id "[ \"\$1\" = -u ] && { echo \"\${FAKE_UID:-1000}\"; exit 0; }; exec /usr/bin/id \"\$@\""

# ---------- a fake release, signed with a throwaway key ----------
export GNUPGHOME=$BASE/gnupg
mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-gen-key 'Installer test <test@example.invalid>' ed25519 sign never 2>/dev/null
gpg --batch --passphrase '' --quick-gen-key 'Other key <other@example.invalid>' ed25519 sign never 2>/dev/null
TEST_FP=$(gpg --list-keys --with-colons test@example.invalid | awk -F: '/^fpr/ {print $10; exit}')
OTHER_FP=$(gpg --list-keys --with-colons other@example.invalid | awk -F: '/^fpr/ {print $10; exit}')
gpg --armor --export "$TEST_FP" >"$BASE/test-key.asc"
# A key whose primary key only certifies and whose subkey signs (gpg then signs with the subkey).
gpg --batch --passphrase '' --quick-gen-key 'Subkey test <sub@example.invalid>' ed25519 cert never 2>/dev/null
SUB_PRIMARY=$(gpg --list-keys --with-colons sub@example.invalid | awk -F: '/^fpr/ {print $10; exit}')
gpg --batch --passphrase '' --quick-add-key "$SUB_PRIMARY" ed25519 sign never 2>/dev/null
gpg --armor --export "$SUB_PRIMARY" >"$BASE/sub-key.asc"
V=0.2.0
make_release() { # DIR [SIGNING_FP]: the .deb sets of the release
  local d=$1 f
  mkdir -p "$d"
  for f in plasma-fusion_${V}-1_all.deb \
           plasma-fusion_${V}-1~neon1_all.deb plasma-fusion-decoration_${V}-1~neon1_amd64.deb \
           plasma-fusion-settings_${V}-1~neon1_amd64.deb plasma-fusion-navigation_${V}-1~neon1_amd64.deb \
           plasma-fusion-quicklook_${V}-1~neon1_amd64.deb plasma-fusion-copytext_${V}-1~neon1_amd64.deb \
           plasma-fusion_${V}-1~testing1_all.deb plasma-fusion-decoration_${V}-1~testing1_amd64.deb \
           plasma-fusion-settings_${V}-1~testing1_amd64.deb plasma-fusion-navigation_${V}-1~testing1_amd64.deb \
           plasma-fusion-quicklook_${V}-1~testing1_amd64.deb plasma-fusion-copytext_${V}-1~testing1_amd64.deb; do
    echo "$f contents" >"$d/$f"
  done
  (cd "$d" && sha256sum ./*.deb | sed 's| \./| |' >SHA256SUMS)
  [ -z "${2:-}" ] || gpg --batch --yes --armor --local-user "$2" --detach-sign -o "$d/SHA256SUMS.asc" "$d/SHA256SUMS"
}
make_release "$BASE/rel-good" "$TEST_FP"
make_release "$BASE/rel-unsigned"
make_release "$BASE/rel-otherkey" "$OTHER_FP"
make_release "$BASE/rel-tampered" "$TEST_FP"
echo "changed" >>"$BASE/rel-tampered/plasma-fusion-decoration_${V}-1~neon1_amd64.deb"
make_release "$BASE/rel-sumsedit" "$TEST_FP"
make_release "$BASE/rel-subkey" "$SUB_PRIMARY"
# The first character of the first sum changed (to 1 where it is 0 already).
sed -i '1{s/^0/1/;t;s/^./0/}' "$BASE/rel-sumsedit/SHA256SUMS"
# As GitHub serves a release: the '~' of the Debian versions became '.' on upload.
make_release "$BASE/rel-github" "$TEST_FP"
for f in "$BASE/rel-github"/*~*; do mv "$f" "${f//\~/.}"; done

# ---------- the cases ----------
osr() { # ID ID_LIKE VERSION_ID CODENAME PRETTY
  mkdir -p "$CASE/root/etc"
  printf 'ID=%s\nID_LIKE="%s"\nVERSION_ID="%s"\nVERSION_CODENAME=%s\nUBUNTU_CODENAME=%s\nPRETTY_NAME="%s"\n' \
    "$1" "$2" "$3" "$4" "$4" "$5" >"$CASE/root/etc/os-release"
}
# run SHELL NAME TOOLS... -- ARGS...: the installer in a fresh fake world; sets RC, OUT, LOG.
run() {
  local sh=$1 tools=() t
  shift
  while [ "$1" != -- ]; do tools+=("$1"); shift; done
  shift
  FB=$CASE/bin
  rm -rf "$FB" && mkdir -p "$FB"
  for t in "${tools[@]}"; do ln -s "$LIB/$t" "$FB/$t"; done
  # An installed Plasma Fusion has its command.
  case " ${VERSIONS:-} " in *" plasma-fusion="*) FAKE_BIN=$FB FAKE_LOG=$CASE/log sh -c "$INSTALLS" ;; esac
  : >"$CASE/log"
  OUT=$(env -i HOME="$CASE/home" PATH="$FB:/usr/bin:/bin" FAKE_BIN="$FB" FAKE_LOG="$CASE/log" \
    FAKE_VERSIONS="${VERSIONS:-}" FAKE_FEDORA="${FEDORA:-}" FAKE_KWIN_RUNNING="${KWIN_RUNNING:-}" FAKE_APT_SIM="${APT_SIM:-}" FAKE_APT_SIM_RC="${APT_SIM_RC:-0}" FAKE_APT_SIM_ERR="${APT_SIM_ERR:-}" \
    FAKE_UID="${UID_FAKE:-1000}" FAKE_PF_VERSION=$V GNUPGHOME="$BASE/no-such-keyring" \
    ${SESSION:+XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=wayland DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/null XDG_RUNTIME_DIR=$CASE} \
    ${DEV:+PLASMA_FUSION_DEV=1 PLASMA_FUSION_DEV_VERSION=$V PLASMA_FUSION_DEV_ROOT=$CASE/root} \
    ${DEV:+PLASMA_FUSION_DEV_KEY=${KEYFILE:-$BASE/test-key.asc} PLASMA_FUSION_DEV_KEY_FP=${KEYFP:-$TEST_FP}} \
    ${RELEASE:+PLASMA_FUSION_DEV_RELEASE_BASE=file://$RELEASE} ${EXTRA_ENV:-} \
    setsid --wait "$sh" "${SCRIPT:-$INSTALLER}" "$@" 2>&1 </dev/null)
  RC=$?
  LOG=$(cat "$CASE/log")
}
expect() { # DESCRIPTION CONDITION...
  local d=$1
  shift
  if "$@"; then ok "$SHNAME: $d"; else bad "$SHNAME: $d"; printf '      rc=%s\n%s\n      log:\n%s\n' "$RC" "$(sed 's/^/      /' <<<"$OUT" | tail -8)" "$(sed 's/^/      /' <<<"$LOG")"; fi
}
has_out() { grep -qF -- "$1" <<<"$OUT"; }
has_log() { grep -qF -- "$1" <<<"$LOG"; }
# No package step and no setup: only queries (rpm, pacman, dpkg-query, busctl) in the log.
no_change() { ! grep -qE '^(sudo|dnf|apt-get|add-apt-repository|yay|paru|makepkg|plasma-fusion) ' <<<"$LOG"; }

FED="rpm sudo dnf busctl id"
AUR="pacman sudo yay busctl id"
DEB="dpkg-query dpkg-deb dpkg sudo apt-get add-apt-repository busctl id"
P675="plasma-workspace=6.7.5 kwin=6.7.5"

shells=(dash bash)
for SHNAME in "${shells[@]}"; do
  sh=$(command -v "$SHNAME") || { echo "SKIP $SHNAME (not installed)"; continue; }
  CASE=$BASE/$SHNAME
  mkdir -p "$CASE/home"
  DEV=1 SESSION=1 VERSIONS=$P675 FEDORA=44 KWIN_RUNNING=6.7.5 RELEASE='' UID_FAKE=1000 EXTRA_ENV='' SCRIPT=''

  # unstamped copy outside test mode
  osr fedora "" 44 "" "Fedora Linux 44"
  DEV='' run "$sh" $FED -- --dry-run
  expect "an unstamped copy refuses outside test mode" [ "$RC" = 3 ]
  expect "  and says why" has_out "not from a release"
  # root
  UID_FAKE=0 run "$sh" $FED -- --dry-run
  expect "root is refused" [ "$RC" = 3 ]
  expect "  with the reason" has_out "not as root"
  # Fedora 44, dry run
  run "$sh" $FED -- --dry-run
  expect "Fedora 44 dry run exits 0" [ "$RC" = 0 ]
  expect "  plans the Copr chroot" has_out "dnf -y copr enable archledger/plasma-fusion fedora-44-x86_64"
  expect "  plans all six packages" has_out "dnf -y install plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation plasma-fusion-quicklook plasma-fusion-copytext"
  expect "  changes nothing" no_change
  # Fedora 44 install
  run "$sh" $FED -- --yes --light
  expect "Fedora 44 install exits 0" [ "$RC" = 0 ]
  expect "  enables Copr through sudo" has_log "sudo dnf -y copr enable archledger/plasma-fusion fedora-44-x86_64"
  expect "  installs the packages in one transaction" has_log "dnf -y install plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation plasma-fusion-quicklook plasma-fusion-copytext"
  expect "  runs the setup as the user with the flag" has_log "plasma-fusion setup --light"
  expect "  setup is not run through sudo" bash -c '! grep -q "^sudo plasma-fusion" <<<"$0"' "$LOG"
  # no terminal and no --yes
  run "$sh" $FED --
  expect "without a terminal or --yes it stops" [ "$RC" = 1 ]
  expect "  before any change" no_change
  # Fedora 43 (no Copr build), old and untested Plasma
  FEDORA=43 run "$sh" $FED -- --dry-run
  expect "Fedora 43 is refused (no Copr build)" [ "$RC" = 3 ]
  VERSIONS="plasma-workspace=6.6.4 kwin=6.6.4" KWIN_RUNNING=6.6.4 run "$sh" $FED -- --dry-run
  expect "Plasma 6.6.4 is refused" [ "$RC" = 3 ]
  expect "  with the update hint" has_out "sudo dnf upgrade --refresh"
  VERSIONS="plasma-workspace=6.8.0 kwin=6.8.0" KWIN_RUNNING=6.8.0 run "$sh" $FED -- --dry-run
  expect "an untested Plasma 6.8 is refused" [ "$RC" = 3 ]
  expect "  naming the tested series" has_out "tested with (Plasma 6.7)"
  VERSIONS="plasma-workspace=6.7.90 kwin=6.7.90" KWIN_RUNNING=6.7.90 run "$sh" $FED -- --dry-run
  expect "a 6.8 beta (6.7.90) is refused" [ "$RC" = 3 ]
  VERSIONS='' run "$sh" $FED -- --dry-run
  expect "no Plasma installed is refused" [ "$RC" = 3 ]
  expect "  with the way to get it" has_out "@kde-desktop-environment"
  # session checks
  SESSION='' run "$sh" $FED -- --dry-run
  expect "outside a Plasma session it refuses" [ "$RC" = 3 ]
  SESSION='' run "$sh" $FED -- --dry-run --package-only
  expect "--package-only works outside a session" [ "$RC" = 0 ]
  expect "  and prints the per-user step" has_out "plasma-fusion setup"
  KWIN_RUNNING=6.7.4 run "$sh" $FED -- --dry-run
  expect "a session older than the installed KWin is refused" [ "$RC" = 3 ]
  expect "  asking to log out and in" has_out "log out and in"
  # already installed; update; uninstall
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- --yes
  expect "an installed Plasma Fusion is left alone by install" [ "$RC" = 0 ]
  expect "  pointing to update" has_out "use 'update'"
  expect "  without changes" no_change
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- update --yes
  expect "update upgrades through dnf" has_log "dnf -y upgrade --refresh plasma-fusion"
  expect "  then plasma-fusion update" has_log "plasma-fusion update"
  # an update from a release before Quick Look and copy text: the four installed are upgraded, the
  # two new ones installed (dnf would refuse to upgrade them)
  P4="plasma-fusion=0.5.0 plasma-fusion-decoration=0.5.0 plasma-fusion-settings=0.5.0 plasma-fusion-navigation=0.5.0"
  VERSIONS="$P675 $P4" run "$sh" $FED -- update --dry-run
  expect "an update plans the upgrade of the installed packages" has_out "dnf -y upgrade --refresh plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation"
  expect "  and the new ones apart" has_out "dnf -y install plasma-fusion-quicklook plasma-fusion-copytext   (new in this release)"
  VERSIONS="$P675 $P4" run "$sh" $FED -- update --yes
  expect "an update from 0.5.0 exits 0" [ "$RC" = 0 ]
  expect "  upgrades the four installed" has_log "dnf -y upgrade --refresh plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation"
  expect "  installs Quick Look and copy text" has_log "dnf -y install plasma-fusion-quicklook plasma-fusion-copytext"
  expect "  then plasma-fusion update" has_log "plasma-fusion update"
  VERSIONS="$P675 $P4 plasma-fusion-quicklook=0.6.0 plasma-fusion-copytext=0.6.0" run "$sh" $FED -- update --yes
  expect "an update with every package installed only upgrades" has_log "dnf -y upgrade --refresh plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation plasma-fusion-quicklook plasma-fusion-copytext"
  expect "  and installs nothing" bash -c '! grep -q "^dnf -y install" <<<"$0"' "$LOG"
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- update --light --yes
  expect "update refuses setup options" [ "$RC" = 3 ]
  VERSIONS="$P675" run "$sh" $FED -- update --yes
  expect "update without an install is refused" [ "$RC" = 3 ]
  mkdir -p "$CASE/bin"
  VERSIONS="$P675 plasma-fusion=0.2.0 plasma-fusion-decoration=0.2.0" run "$sh" $FED -- uninstall --yes --package-only
  expect "uninstall removes the installed packages only" has_log "dnf -y remove plasma-fusion plasma-fusion-decoration"
  expect "  (not the ones that are not installed)" bash -c '! grep -q "remove.*settings" <<<"$0"' "$LOG"
  osr arch "" "" "" "Arch Linux"
  VERSIONS="$P675 plasma-fusion=0.2.0 plasma-fusion-decoration=0.2.0 plasma-fusion-debug=0.2.0" run "$sh" $AUR -- uninstall --yes --package-only
  expect "Arch uninstall also removes the AUR helper's debug package" has_log "pacman -Rns --noconfirm plasma-fusion plasma-fusion-decoration plasma-fusion-debug"
  osr fedora "" 44 "" "Fedora Linux 44"
  # uninstall undoes the login screen and boot splash looks first (they point at package files)
  SYSD=$CASE/root/usr/share/plasma-fusion/tools/system
  mkdir -p "$SYSD" "$CASE/root/usr/share/plymouth/themes/plasma-fusion"
  for t in greeter-restore.sh plymouth-uninstall.sh; do
    printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >>"$FAKE_LOG"\nexit ${FAKE_SYS_RC:-0}\n' "$t" >"$SYSD/$t"
    chmod +x "$SYSD/$t"
  done
  printf '[General]\nNumlock=none\n\n# Plasma Fusion: login screen wallpaper (greeter-apply.sh; undo: greeter-restore.sh)\n[Greeter]\nWallpaperPlugin=org.kde.image\n' \
    >"$CASE/root/etc/plasmalogin.conf"
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- uninstall --yes --package-only
  expect "uninstall restores a login screen Plasma Fusion styled" has_log "greeter-restore.sh"
  expect "  and removes the boot splash" has_log "plymouth-uninstall.sh"
  expect "  both before the packages go" bash -c 'g=$(grep -n "^greeter-restore.sh" <<<"$0" | cut -d: -f1); r=$(grep -n "^dnf -y remove" <<<"$0" | cut -d: -f1); [ -n "$g" ] && [ -n "$r" ] && [ "$g" -lt "$r" ]' "$LOG"
  expect "  and the plan says so" has_out "greeter-restore.sh   (the login screen"
  EXTRA_ENV="FAKE_SYS_RC=1" VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- uninstall --yes --package-only
  expect "a failed login screen restore keeps the packages" bash -c '[ "$1" = 1 ] && ! grep -q "^dnf -y remove" <<<"$0"' "$LOG" "$RC"
  printf '[General]\nNumlock=none\n' >"$CASE/root/etc/plasmalogin.conf"
  rm -r "$CASE/root/usr/share/plymouth/themes/plasma-fusion"
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- uninstall --yes --package-only
  expect "an unstyled login screen and no splash are left alone" bash -c '! grep -qE "greeter-restore|plymouth-uninstall" <<<"$0"' "$LOG"
  # A styled login screen without the mark: greeter-apply.sh wrote plain keys into an existing
  # [Greeter] group (or the Login Screen settings rewrote the file since).
  printf '[Greeter]\nWallpaperPlugin=org.kde.image\n\n[Greeter][Wallpaper][org.kde.image][General]\nImage=file:///usr/share/plasma-fusion/backgrounds/dusk-ridge-dark-login.png\n' \
    >"$CASE/root/etc/plasmalogin.conf"
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- uninstall --yes --package-only
  expect "a styled login screen without the mark is restored too" has_log "greeter-restore.sh"
  # Only the greeter user's Global Theme says so (the wallpaper keys were changed since).
  printf '[General]\nNumlock=none\n' >"$CASE/root/etc/plasmalogin.conf"
  mkdir -p "$CASE/root/var/lib/plasmalogin/.config"
  printf '[KDE]\nLookAndFeelPackage=org.plasmafusion.dark.desktop\n' >"$CASE/root/var/lib/plasmalogin/.config/kdeglobals"
  fake getent '[ "$1 $2" = "passwd plasmalogin" ] && echo "plasmalogin:x:975:975::/var/lib/plasmalogin:/sbin/nologin"'
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED getent -- uninstall --yes --package-only
  expect "a greeter on Plasma Fusion's Global Theme is restored too" has_log "greeter-restore.sh"
  rm -rf "$CASE/root/var/lib/plasmalogin"
  printf '[General]\nNumlock=none\n' >"$CASE/root/etc/plasmalogin.conf"
  # SDDM: greeter-apply.sh chose the Plasma Fusion theme (its backup says greeter=sddm).
  mkdir -p "$CASE/root/var/lib/plasma-fusion/greeter-backup-20261021T000000Z" "$CASE/root/etc/sddm.conf.d"
  printf 'created=20261021T000000Z\ngreeter=sddm\nbefore=other\n' >"$CASE/root/var/lib/plasma-fusion/greeter-backup-20261021T000000Z/info"
  printf '[Theme]\nCurrent=plasmafusion\nCursorTheme=PlasmaFusion-cursors\n' >"$CASE/root/etc/sddm.conf.d/kde_settings.conf"
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- uninstall --yes --package-only
  expect "an SDDM login screen Plasma Fusion chose is restored too, SDDM's runs only" has_log "greeter-restore.sh --greeter sddm"
  expect "  (plasma-login-manager's are not replayed)" bash -c '! grep -q "^greeter-restore.sh *$\|--greeter plasmalogin" <<<"$0"' "$LOG"
  # The same with comments after the values, which SDDM cuts off
  printf '[Theme]\nCurrent=plasmafusion # chosen here\nCursorTheme=PlasmaFusion-cursors # too\n' >"$CASE/root/etc/sddm.conf.d/kde_settings.conf"
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- uninstall --yes --package-only
  expect "  also with a comment after the value" has_log "greeter-restore.sh --greeter sddm"
  # A choice of the theme greeter-apply.sh did not make: the uninstall goes on and names the file
  printf '[Theme]\nCurrent=plasmafusion # by hand\n' >"$CASE/root/etc/sddm.conf"
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- uninstall --yes --package-only
  expect "a theme chosen elsewhere is named, and the packages still go" bash -c 'grep -q "still chooses the Plasma Fusion login theme (.*/etc/sddm.conf)" <<<"$0" && grep -q "^dnf -y remove" <<<"$1"' "$OUT" "$LOG"
  rm -f "$CASE/root/etc/sddm.conf"
  # That run undone since (another theme chosen): the old backup asks for nothing.
  printf '[Theme]\nCurrent=breeze\n' >"$CASE/root/etc/sddm.conf.d/kde_settings.conf"
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- uninstall --yes --package-only
  expect "a backup of an SDDM run undone since asks for no restore" bash -c '! grep -q "greeter-restore" <<<"$0"' "$LOG"
  # Both greeters: a styled plasma-login-manager is restored on its own.
  printf '[Greeter]\nWallpaperPlugin=org.kde.image\n\n[Greeter][Wallpaper][org.kde.image][General]\nImage=file:///usr/share/plasma-fusion/backgrounds/dusk-ridge-dark-login.png\n' \
    >"$CASE/root/etc/plasmalogin.conf"
  VERSIONS="$P675 plasma-fusion=0.2.0" run "$sh" $FED -- uninstall --yes --package-only
  expect "with SDDM backups on record, plasma-login-manager is restored with --greeter plasmalogin" has_log "greeter-restore.sh --greeter plasmalogin"
  printf '[General]\nNumlock=none\n' >"$CASE/root/etc/plasmalogin.conf"
  rm -rf "$CASE/root/var/lib/plasma-fusion" "$CASE/root/etc/sddm.conf.d"
  # the optional system steps are offered where they apply
  rm -f "$CASE/root/etc/plasmalogin.conf"
  run "$sh" $FED -- --yes
  expect "without plasma-login-manager no login screen step is offered" bash -c '! grep -q "greeter-apply" <<<"$0"' "$OUT"
  expect "  the Fedora boot splash is" has_out "plymouth-install.sh"
  mkdir -p "$CASE/root/usr/lib/plasmalogin"
  run "$sh" $FED -- --yes
  expect "with plasma-login-manager the login screen step is offered" has_out "greeter-apply.sh"
  rm -rf "$CASE/root/usr/lib/plasmalogin"
  mkdir -p "$CASE/root/usr/bin"
  printf '#!/bin/sh\n' >"$CASE/root/usr/bin/sddm-greeter-qt6"
  chmod +x "$CASE/root/usr/bin/sddm-greeter-qt6"
  run "$sh" $FED -- --yes
  expect "with SDDM's Qt 6 greeter the login screen step is offered" has_out "greeter-apply.sh"
  rm -rf "$CASE/root/usr/bin/sddm-greeter-qt6" "$CASE/root/usr/share/plasma-fusion" "$CASE/root/usr/share/plymouth"
  # setup failure
  EXTRA_ENV="FAKE_SETUP_RC=1" run "$sh" $FED -- --yes
  expect "a failed setup exits 1" [ "$RC" = 1 ]
  expect "  and names the way back" has_out "plasma-fusion restore --latest"
  # Fedora Atomic, RHEL family
  mkdir -p "$CASE/root/run" && : >"$CASE/root/run/ostree-booted"
  run "$sh" $FED -- --dry-run
  expect "Fedora Atomic prints the rpm-ostree steps" has_out "rpm-ostree install plasma-fusion"
  expect "  and exits 0" [ "$RC" = 0 ]
  rm -f "$CASE/root/run/ostree-booted"
  osr almalinux "rhel centos fedora" 10 "" "AlmaLinux 10"
  FEDORA='' run "$sh" $FED -- --dry-run
  expect "the RHEL family is refused" [ "$RC" = 3 ]
  # environment cannot redirect a release copy
  STAMPED=$CASE/install-stamped.sh
  "$ROOT/packaging/stamp-installer.sh" --copr "44" --ppa stonking --deb "neon testing" "$STAMPED" >/dev/null
  osr fedora "" 44 "" "Fedora Linux 44"
  DEV='' SCRIPT=$STAMPED EXTRA_ENV="DEV_DNF_REPO=http://evil.invalid RELEASE_BASE=http://evil.invalid PLASMA_FUSION_DEV_DNF_REPO=http://evil.invalid" run "$sh" $FED -- --dry-run
  expect "a stamped copy ignores test endpoints in the environment" bash -c '! grep -q evil <<<"$0$1"' "$OUT" "$LOG"
  expect "  (it runs as a release)" bash -c '! grep -q "test mode" <<<"$0"' "$OUT"
  # Arch
  osr arch "" "" "" "Arch Linux"
  run "$sh" $AUR -- --yes
  expect "Arch builds the AUR packages with yay" has_log "yay -S --needed --noconfirm plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation plasma-fusion-quicklook plasma-fusion-copytext"
  expect "  without sudo around yay" bash -c '! grep -q "^sudo yay" <<<"$0"' "$LOG"
  osr endeavouros arch "" "" "EndeavourOS"
  run "$sh" pacman sudo busctl id -- --yes
  expect "an Arch derivative without a helper gets the makepkg steps" has_out "makepkg -si"
  expect "  exit 3, nothing changed" [ "$RC" = 3 ]
  osr arch "" "" "" "Arch Linux"
  EXTRA_ENV="PLASMA_FUSION_DEV_AUR_SRC=$CASE" run "$sh" pacman sudo makepkg busctl id -- --yes
  expect "a test PKGBUILD is built with makepkg -si" has_log "makepkg -si --noconfirm"
  # Ubuntu
  osr ubuntu debian 26.10 stonking "Ubuntu 26.10"
  run "$sh" $DEB -- --yes
  expect "Kubuntu 26.10 adds the PPA" has_log "add-apt-repository -y ppa:archledger/plasma-fusion"
  expect "  and offers the boot splash step there too" has_out "plymouth-install.sh --select"
  expect "  and installs the six packages" has_log "apt-get install -y plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation plasma-fusion-quicklook plasma-fusion-copytext"
  # an update from a release before Quick Look and copy text (apt's --only-upgrade would skip them)
  VERSIONS="$P675 $P4" run "$sh" $DEB -- update --yes
  expect "a PPA update upgrades the four installed" has_log "apt-get install -y --only-upgrade plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation"
  expect "  and installs the new ones" has_log "apt-get install -y plasma-fusion-quicklook plasma-fusion-copytext"
  APT_SIM='Inst plasma-workspace [4:6.7.5-0ubuntu1] (4:6.8.0-0ubuntu1 Ubuntu:26.10 [amd64])\n' run "$sh" $DEB -- --yes
  expect "a PPA install that would upgrade part of Plasma is refused" [ "$RC" = 3 ]
  expect "  the PPA stays, nothing installed" bash -c 'grep -q "The PPA stays added; nothing was installed" <<<"$0" && ! grep -q "^apt-get install -y plasma-fusion" <<<"$1"' "$OUT" "$LOG"
  APT_SIM='Inst kwin-wayland [4:6.7.5-0ubuntu1] (4:6.8.0-0ubuntu1 Ubuntu:26.10 [amd64])\n' VERSIONS="$P675 $P4" run "$sh" $DEB -- update --yes
  expect "a PPA update that would upgrade part of Plasma is refused" [ "$RC" = 3 ]
  expect "  nothing upgraded" bash -c '! grep -q "^apt-get install -y --only-upgrade" <<<"$0"' "$LOG"
  osr ubuntu debian 26.04 resolute "Ubuntu 26.04 LTS"
  VERSIONS="plasma-workspace=6.6.6 kwin=6.6.6" KWIN_RUNNING=6.6.6 run "$sh" $DEB -- --dry-run
  expect "Kubuntu 26.04 (Plasma 6.6) is refused" [ "$RC" = 3 ]
  osr linuxmint "ubuntu debian" 22 wilma "Linux Mint 22"
  VERSIONS='' run "$sh" $DEB -- --dry-run
  expect "Mint without Plasma is refused" [ "$RC" = 3 ]
  # KDE neon and Debian testing: the release's .deb sets
  osr neon "ubuntu debian" 24.04 noble "KDE neon User Edition"
  RELEASE=$BASE/rel-good run "$sh" $DEB -- --yes
  expect "neon installs the neon .deb set" has_log "plasma-fusion-navigation_${V}-1~neon1_amd64.deb"
  expect "  all six in one apt call" bash -c 'grep -c "^apt-get install -y .*plasma-fusion_.*~neon1_all.deb.*decoration.*settings.*navigation.*quicklook.*copytext" <<<"$0" | grep -q 1' "$LOG"
  expect "  says the signature verified" has_out "signature verified"
  # a neon still at Plasma 6.7.5 while the release was built for 6.8.0: apt would upgrade KWin and
  # libplasma with it and keep plasmashell 6.7.5 (2026-10-18)
  BEHIND_SIM='Inst kwin-wayland [4:6.7.5-0zneon1] (4:6.8.0-0zneon1 KDE neon:noble [amd64])\nInst libplasma6 [6.7.5-0zneon1] (6.8.0-0zneon1 KDE neon:noble [amd64])\nInst plasma-fusion (0.2.0-1~neon1 local-deb [all])\n'
  APT_SIM=$BEHIND_SIM RELEASE=$BASE/rel-good run "$sh" $DEB -- --yes
  expect "neon behind the release's Plasma is refused" [ "$RC" = 3 ]
  expect "  naming what apt would upgrade" has_out "would also upgrade part of Plasma (kwin-wayland 4:6.7.5-0zneon1 -> 4:6.8.0-0zneon1, libplasma6 6.7.5-0zneon1 -> 6.8.0-0zneon1)"
  expect "  saying how to update first" has_out "KDE neon: sudo pkcon update"
  expect "  nothing installed" bash -c '! grep -q "^apt-get install" <<<"$0"' "$LOG"
  APT_SIM=$BEHIND_SIM RELEASE=$BASE/rel-good run "$sh" $DEB -- --dry-run
  expect "  and so is its dry run (the .debs checked before the plan)" [ "$RC" = 3 ]
  expect "  which names it too" has_out "would also upgrade part of Plasma (kwin-wayland"
  APT_SIM_RC=100 APT_SIM_ERR='E: Unable to correct problems, you have held broken packages.' RELEASE=$BASE/rel-good run "$sh" $DEB -- --yes
  expect "a failed apt dry run stops it" [ "$RC" = 1 ]
  expect "  with apt's words" has_out "apt's dry run of the install failed, so nothing was installed: E: Unable to correct problems"
  expect "  nothing installed" bash -c '! grep -q "^apt-get install" <<<"$0"' "$LOG"
  APT_SIM='Inst plasma-fusion (0.2.0-1~neon1 local-deb [all])\nInst tesseract-ocr (5.3.4-1 Ubuntu:24.04 [amd64])\nInst libc6 [2.39-0ubuntu8] (2.39-0ubuntu9 Ubuntu:24.04 [amd64])\n' \
    RELEASE=$BASE/rel-good run "$sh" $DEB -- --yes
  expect "an install that upgrades nothing of Plasma goes on" has_log "apt-get install -y"
  osr debian "" "" forky "Debian GNU/Linux forky/sid"
  RELEASE=$BASE/rel-good run "$sh" $DEB -- --yes
  expect "Debian testing installs the testing set" has_log "plasma-fusion-settings_${V}-1~testing1_amd64.deb"
  # GitHub renames the files ('~' -> '.'); the installer finds them and checks them by their names.
  RELEASE=$BASE/rel-github run "$sh" $DEB -- --yes
  expect "Debian testing installs from GitHub's renamed files" [ "$RC" = 0 ]
  expect "  the whole testing set" has_log "plasma-fusion-navigation_${V}-1~testing1_amd64.deb"
  osr neon "ubuntu debian" 24.04 noble "KDE neon User Edition"
  RELEASE=$BASE/rel-github run "$sh" $DEB -- --yes
  expect "neon installs from GitHub's renamed files" has_log "plasma-fusion-decoration_${V}-1~neon1_amd64.deb"
  osr debian "" "" forky "Debian GNU/Linux forky/sid"
  osr pika "ubuntu debian" 26.10 stonking "Another derivative"
  RELEASE=$BASE/rel-good run "$sh" $DEB -- --yes
  expect "another derivative gets the shared part only" has_log "plasma-fusion_${V}-1_all.deb"
  expect "  and is told what is left out" has_out "no build of the compiled parts (the window decoration, settings page, tablet gestures, Quick Look and copy text's selection)"
  osr debian "" 13 trixie "Debian GNU/Linux 13"
  VERSIONS="plasma-workspace=6.3.6 kwin=6.3.6" RELEASE=$BASE/rel-good run "$sh" $DEB -- --dry-run
  expect "Debian 13 (Plasma 6.3) is refused" [ "$RC" = 3 ]
  # integrity
  osr neon "ubuntu debian" 24.04 noble "KDE neon User Edition"
  RELEASE=$BASE/rel-unsigned run "$sh" $DEB -- --yes
  expect "a missing signature stops it" [ "$RC" = 1 ]
  expect "  saying so" has_out "SHA256SUMS.asc is missing"
  expect "  nothing installed" bash -c '! grep -q "^apt-get install" <<<"$0"' "$LOG"
  RELEASE=$BASE/rel-otherkey run "$sh" $DEB -- --yes
  expect "a signature by another key stops it" [ "$RC" = 1 ]
  expect "  nothing installed" bash -c '! grep -q "^apt-get install" <<<"$0"' "$LOG"
  RELEASE=$BASE/rel-sumsedit run "$sh" $DEB -- --yes
  expect "an edited SHA256SUMS fails its signature" [ "$RC" = 1 ]
  RELEASE=$BASE/rel-tampered run "$sh" $DEB -- --yes
  expect "a tampered package fails its checksum" [ "$RC" = 1 ]
  expect "  saying so" has_out "checksum mismatch"
  expect "  nothing installed" bash -c '! grep -q "^apt-get install" <<<"$0"' "$LOG"
  KEYFILE=$BASE/sub-key.asc KEYFP=$SUB_PRIMARY RELEASE=$BASE/rel-subkey run "$sh" $DEB -- --yes
  expect "a signature by a subkey of the pinned key is accepted" has_log "apt-get install -y"
  KEYFILE=$BASE/sub-key.asc KEYFP=$SUB_PRIMARY RELEASE=$BASE/rel-good run "$sh" $DEB -- --yes
  expect "  and the pinned key's fingerprint is what counts" [ "$RC" = 1 ]
  RELEASE=$BASE/rel-unsigned run "$sh" $DEB -- --yes --insecure-no-sig
  expect "--insecure-no-sig installs on checksums alone" has_log "apt-get install -y"
  VERSIONS="$P675 plasma-fusion=0.3.0" RELEASE=$BASE/rel-good run "$sh" $DEB -- update --yes
  expect "no downgrade from 0.3.0 to 0.2.0" [ "$RC" = 3 ]
  expect "  nothing installed" bash -c '! grep -q "^apt-get install" <<<"$0"' "$LOG"
  # NixOS
  osr nixos "" 26.11 "" "NixOS 26.11"
  run "$sh" nix-store id -- --dry-run
  expect "NixOS prints the flake lines" has_out "plasma-fusion.nixosModules.default"
  expect "  pinned to the release tag" has_out "github:archledger/plasma-fusion/v$V"
  expect "  exits 0 without sudo" [ "$RC" = 0 ]
  VERSIONS="plasma-workspace=6.6.6 kwin=6.6.6" run "$sh" nix-store id -- --dry-run
  expect "NixOS 26.05 (Plasma 6.6) is refused" [ "$RC" = 3 ]
  # truncated downloads run nothing
  osr fedora "" 44 "" "Fedora Linux 44"
  size=$(stat -c %s "$INSTALLER")
  ran=0
  for cut in 200 1000 4000 9000 $((size / 2)) $((size - 40)) $((size - 12)); do
    head -c "$cut" "$INSTALLER" >"$CASE/truncated.sh"
    SCRIPT=$CASE/truncated.sh run "$sh" $FED -- --yes
    [ -z "$LOG" ] || ran=1
    if [ "$cut" -ge "$((size / 2))" ] && has_out "Plasma Fusion $V installer"; then ran=1; fi
  done
  expect "a truncated download runs nothing" [ "$ran" = 0 ]
done

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
