#!/bin/sh
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion installer: detects the system, installs the Plasma Fusion packages through its
# channel and runs the per-user setup in your Plasma session (docs/parts/installer.md).
#
#   curl -fsSL https://github.com/archledger/plasma-fusion/releases/latest/download/install.sh | sh
#   ... | sh -s -- update | uninstall | status
#   ... | sh -s -- --dry-run          check everything, print the plan, change nothing
#
# Channels:
#   Fedora                  the signed Copr repository archledger/plasma-fusion (dnf)
#   Fedora Atomic           prints the rpm-ostree steps
#   Arch and derivatives    the AUR (yay or paru; otherwise prints the makepkg steps)
#   Ubuntu / Kubuntu        the signed PPA ppa:archledger/plasma-fusion, for the series it builds
#   KDE neon, Debian        the release's .deb packages built for that system, checked against the
#   testing/unstable        signed SHA256SUMS; other Debian-family systems with Plasma 6.7 or later
#                           get the shared part only (the compiled parts need a matching build)
#   NixOS                   prints the flake or module lines; never edits /etc/nixos
#
# Options: --yes (no question; needed without a terminal), --dry-run, --package-only (packages only,
# no setup step: SSH, or for other users), --light, --dark, --auto, --keep-layout, --keep-shortcuts
# (passed to plasma-fusion setup), --insecure-no-sig (release files: HTTPS and SHA256 only).
# Exit codes: 0 done or nothing to do, 1 error, 2 usage, 3 refused (nothing changed), 4 declined.
#
# Integrity: dnf and apt check the Copr and PPA signatures; the AUR package builds the signed git tag;
# release files are checked against SHA256SUMS, whose signature must verify against the pinned key
# below (a missing signature stops the installer). Safety: it runs as your user and asks for sudo
# for the package step only; it checks everything before it asks; it never downgrades; it installs
# neither Plasma nor a login screen or boot splash; the whole script is one function, so a
# truncated download does nothing. Read it first:
#   curl -fsSLO https://github.com/archledger/plasma-fusion/releases/latest/download/install.sh

# Stamped by the release (packaging/stamp-installer.sh); an unstamped copy runs only for tests.
PF_VERSION='@PF_VERSION@'
PF_PLASMA_SERIES='@PF_PLASMA_SERIES@'
PF_COPR_FEDORA='@PF_COPR_FEDORA@'
PF_PPA_SERIES='@PF_PPA_SERIES@'
PF_DEB_TARGETS='@PF_DEB_TARGETS@'

REPO=archledger/plasma-fusion
PKGS="plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation"
# The release signing key (it also signs the git tags), pinned: the release's SHA256SUMS must carry
# its signature. Imported into a temporary keyring only; your own keyring is never touched.
KEY_FP=F35053398E3C80FE20891B82C10B8492BD7F30C6
KEY_ASC='-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEakb95BYJKwYBBAHaRw8BAQdAdjfw/0t9/UGFY1GvBHAyZAhz7IHF03DhtA2S
UYW/UbO0JGFyY2hsZWRnZXIgPGFyY2hsZWRnZXIyMzZAZ21haWwuY29tPoiZBBMW
CgBBFiEE81BTOY48gP4giRuCwQuEkr1/MMYFAmpG/eQCGwMFCQPCZwAFCwkIBwIC
IgIGFQoJCAsCBBYCAwECHgcCF4AACgkQwQuEkr1/MMbFLwD/dg3YhbBk4SFKVTeh
OVaN4hHNC2WQGSEIxmgWcw+bvokBAKprgT0zy7fyVzO3Za4V8BGaSWypCWCLA4Uv
PLCYfTcC
=PsGk
-----END PGP PUBLIC KEY BLOCK-----'

say() { printf '[plasma-fusion] %s\n' "$*" >&2; }
warn() { printf '[plasma-fusion] warning: %s\n' "$*" >&2; }
die() { printf '[plasma-fusion] %s\n' "$*" >&2; exit 1; }
refuse() { printf '[plasma-fusion] %s\n' "$*" >&2; say "Nothing was changed."; exit 3; }
has() { command -v "$1" >/dev/null 2>&1; }

# ver_ge A B: version A >= B (dotted numbers).
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]; }
# The Plasma series of a version: 6.7.5 is 6.7; a beta (6.7.80, 6.7.90) belongs to 6.8.
series_of() {
  printf '%s\n' "$1" | awk -F. '{ m = $2; if ($3 + 0 >= 80) m++; print $1 "." m }'
}
in_list() { # WORD LIST
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

# Upstream version of an installed package (no epoch, no release), empty when not installed.
pkg_version() {
  case $LANE in
    copr | atomic) rpm -q --qf '%{VERSION}\n' "$1" 2>/dev/null | grep -E '^[0-9]' | head -n 1 ;;
    aur) pacman -Q "$1" 2>/dev/null | awk '{print $2}' | sed 's/^[0-9]*://; s/-[^-]*$//' ;;
    ppa | deb)
      dpkg-query -W -f '${db:Status-Status} ${Version}\n' "$1" 2>/dev/null | awk '$1 == "installed" {print $2}' |
        sed 's/^[0-9]*://; s/-[^-]*$//' | grep -oE '^[0-9][0-9.]*' | sed 's/\.$//' ;;
    nix)
      ns=$(command -v nix-store || echo /run/current-system/sw/bin/nix-store)
      "$ns" --query --requisites /run/current-system/sw 2>/dev/null |
        sed -n "s|^/nix/store/[a-z0-9]*-$1-\([0-9][0-9.]*\)\$|\1|p" | head -n 1 ;;
  esac
}
# Full installed version of a Plasma Fusion package (for the no-downgrade check), empty if none.
pf_installed() {
  case $LANE in
    copr | atomic) rpm -q --qf '%{VERSION}-%{RELEASE}\n' "$1" 2>/dev/null | grep -E '^[0-9]' | head -n 1 ;;
    aur) pacman -Q "$1" 2>/dev/null | awk '{print $2}' ;;
    ppa | deb) dpkg-query -W -f '${db:Status-Status} ${Version}\n' "$1" 2>/dev/null | awk '$1 == "installed" {print $2}' ;;
    *) : ;;
  esac
}

# ---------- detection ----------

detect_lane() {
  osr=$TEST_ROOT/etc/os-release
  [ -r "$osr" ] || osr=$TEST_ROOT/usr/lib/os-release
  [ -r "$osr" ] || refuse "cannot read os-release; unsupported system."
  # Read the keys in a subshell: os-release's variables never enter this script's scope.
  eval "$(
    # shellcheck disable=SC1090
    . "$osr"
    for k in ID ID_LIKE VERSION_ID VERSION_CODENAME UBUNTU_CODENAME VARIANT_ID PRETTY_NAME; do
      eval "v=\${$k:-}"
      printf "OS_%s='%s'\n" "$k" "$(printf '%s' "$v" | sed "s/'/'\\\\''/g")"
    done
  )"
  family=" $OS_ID $OS_ID_LIKE "
  SERIES=${OS_UBUNTU_CODENAME:-$OS_VERSION_CODENAME}
  LANE='' DEB_TAG=''
  if [ "$OS_ID" = nixos ]; then
    LANE=nix
  elif case $family in *" fedora "*) true ;; *) false ;; esac; then
    if [ -e "$TEST_ROOT/run/ostree-booted" ]; then
      LANE=atomic
    else
      FEDORA=$(rpm -E %fedora 2>/dev/null || true)
      case $FEDORA in '' | *[!0-9]*) refuse "$OS_PRETTY_NAME: only Fedora itself has a Plasma Fusion repository (Copr)." ;; esac
      in_list "$FEDORA" "$PF_COPR_FEDORA" ||
        refuse "Fedora $FEDORA has no Plasma Fusion build (the Copr repository builds Fedora $PF_COPR_FEDORA)."
      LANE=copr
    fi
  elif [ "$OS_ID" = steamos ]; then
    refuse "SteamOS has a read-only system image; Plasma Fusion cannot be installed on it."
  elif case $family in *" arch "*) true ;; *) false ;; esac; then
    LANE=aur
  elif [ "$OS_ID" = neon ]; then
    LANE=deb DEB_TAG=neon
  elif [ "$OS_ID" = ubuntu ] && in_list "$SERIES" "$PF_PPA_SERIES"; then
    LANE=ppa
  elif [ "$OS_ID" = debian ] && case " $OS_VERSION_CODENAME " in " forky " | " sid " | "  ") true ;; *) false ;; esac; then
    LANE=deb DEB_TAG=testing
  elif case $family in *" debian "* | *" ubuntu "*) true ;; *) false ;; esac; then
    LANE=deb DEB_TAG=
  else
    refuse "unrecognised system ($OS_PRETTY_NAME, ID=$OS_ID); see docs/parts/installer.md for the supported ones."
  fi
}

# The version of the KWin that runs this session (D-Bus; no Plasma program is started).
running_kwin() {
  has busctl || return 0
  busctl --user call org.kde.KWin /KWin org.kde.KWin supportInformation 2>/dev/null |
    grep -o 'KWin version: [0-9][0-9.]*' | head -n 1 | sed 's/KWin version: //'
}

check_plasma() {
  PLASMA=$(pkg_version plasma-workspace)
  KWIN=$(pkg_version kwin)
  [ -n "$KWIN" ] || KWIN=$(pkg_version kwin-wayland)
  if [ -z "$PLASMA" ]; then
    case $LANE in
      copr) refuse "Plasma is not installed. This installer does not install Plasma: sudo dnf install @kde-desktop-environment, log in to Plasma, then run it again." ;;
      aur) refuse "Plasma is not installed. This installer does not install Plasma: sudo pacman -S plasma-meta, log in to Plasma, then run it again." ;;
      nix) refuse "Plasma is not in this NixOS system (services.desktopManager.plasma6.enable = true)." ;;
      *) refuse "Plasma is not installed. This installer does not install Plasma." ;;
    esac
  fi
  ver_ge "$PLASMA" 6.7 || {
    case $LANE in
      copr) refuse "Plasma $PLASMA is too old (6.7 or later is needed): sudo dnf upgrade --refresh, reboot, then run this again." ;;
      nix) refuse "Plasma $PLASMA is too old (6.7 or later): NixOS 26.11 or nixos-unstable has it." ;;
      ppa | deb) refuse "Plasma $PLASMA is too old (6.7 or later is needed); Kubuntu 26.10 and Debian testing have 6.7." ;;
      *) refuse "Plasma $PLASMA is too old (6.7 or later is needed)." ;;
    esac
  }
  s=$(series_of "$PLASMA")
  in_list "$s" "$PF_PLASMA_SERIES" ||
    refuse "Plasma $PLASMA is newer than Plasma Fusion $PF_VERSION was tested with (Plasma $PF_PLASMA_SERIES). A release tested with Plasma $s will follow."
}

check_session() {
  [ "$PACKAGE_ONLY" = 1 ] && return 0
  case "${XDG_CURRENT_DESKTOP:-}" in *KDE*) : ;; *)
    refuse "run this in a terminal inside your Plasma session (or use --package-only and run 'plasma-fusion setup' there later)." ;;
  esac
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] ||
    refuse "no session bus: run this in a terminal inside your Plasma session (or use --package-only)."
  [ "${XDG_SESSION_TYPE:-}" = wayland ] || warn "this is not a Wayland session; Plasma Fusion is tested on Wayland."
  running=$(running_kwin)
  if [ -n "$running" ] && [ -n "$KWIN" ] && [ "$running" != "$KWIN" ]; then
    refuse "Plasma was updated since you logged in (KWin $running runs, $KWIN is installed): log out and in, then run this again."
  fi
}

# ---------- release files ----------

# Fetch and verify SHA256SUMS into $TMP (once).
fetch_sums() {
  [ -s "$TMP/SHA256SUMS" ] && return 0
  curl -fsSL "$RELEASE_BASE/SHA256SUMS" -o "$TMP/SHA256SUMS" || die "could not fetch SHA256SUMS of Plasma Fusion $PF_VERSION."
  if [ "$INSECURE" = 1 ]; then
    warn "--insecure-no-sig: the release signature is not checked (HTTPS and SHA256 only)."
    return 0
  fi
  has gpg || die "gpg is needed to check the release signature: install gnupg (or, not recommended, use --insecure-no-sig)."
  curl -fsSL "$RELEASE_BASE/SHA256SUMS.asc" -o "$TMP/SHA256SUMS.asc" ||
    die "SHA256SUMS.asc is missing: every Plasma Fusion release is signed, so the download may have been tampered with. Nothing was installed."
  mkdir -p "$TMP/gnupg" && chmod 700 "$TMP/gnupg"
  printf '%s\n' "$KEY_ASC" | GNUPGHOME=$TMP/gnupg gpg --batch --import >/dev/null 2>&1 || die "could not import the pinned release key."
  # VALIDSIG's last field is the primary key's fingerprint, the first the signing (sub)key's: a
  # signature by any subkey of the pinned key counts, nothing else does.
  GNUPGHOME=$TMP/gnupg gpg --batch --status-fd 1 --verify "$TMP/SHA256SUMS.asc" "$TMP/SHA256SUMS" 2>/dev/null |
    awk -v fp="$KEY_FP" '$1 == "[GNUPG:]" && $2 == "VALIDSIG" && $NF == fp { ok = 1 } END { exit !ok }' ||
    die "SHA256SUMS is not signed by the Plasma Fusion release key $KEY_FP; refusing to install."
  say "release checksums: signature verified (key $KEY_FP)"
}
# Download one release file named in SHA256SUMS and check it; prints its path.
fetch_asset() {
  line=$(awk -v n="$1" '$2 == n || $2 == "*" n' "$TMP/SHA256SUMS")
  [ "$(printf '%s\n' "$line" | grep -c .)" = 1 ] || die "$1 is not in the release's SHA256SUMS."
  # GitHub renames release files on upload: a character other than a letter, digit, '-', '_' or '.'
  # becomes '.' (the '~' of the Debian versions), so the file may sit there under that name.
  gh_name=$(printf '%s\n' "$1" | sed 's/[^A-Za-z0-9._-]/./g')
  curl -fsSL "$RELEASE_BASE/$1" -o "$TMP/$1" 2>/dev/null ||
    { [ "$gh_name" != "$1" ] && curl -fsSL "$RELEASE_BASE/$gh_name" -o "$TMP/$1"; } ||
    die "download of $1 failed."
  (cd "$TMP" && printf '%s\n' "$line" | sha256sum -c - >/dev/null 2>&1) || die "checksum mismatch on $1; refusing to install."
  printf '%s\n' "$TMP/$1"
}
# The .deb set for this system: a target build when the release has one, else the shared part.
deb_assets() {
  fetch_sums
  names=$(awk '{print $2}' "$TMP/SHA256SUMS" | sed 's/^\*//')
  # The version inside the patterns below, its dots and plus signs taken literally.
  vre=$(printf '%s' "$PF_VERSION" | sed 's/[.+]/\\&/g')
  DEBS='' DEB_PARTIAL=0
  if [ -n "$DEB_TAG" ] && in_list "$DEB_TAG" "$PF_DEB_TARGETS"; then
    for p in $PKGS; do
      n=$(printf '%s\n' "$names" | grep -E "^${p}_${vre}-[0-9]+~${DEB_TAG}[0-9]+_(all|amd64)\.deb\$" || true)
      [ "$(printf '%s\n' "$n" | grep -c .)" = 1 ] || die "the release has no single $p package for $DEB_TAG."
      DEBS="$DEBS $n"
    done
  else
    n=$(printf '%s\n' "$names" | grep -E "^plasma-fusion_${vre}-[0-9]+_all\.deb\$" || true)
    [ "$(printf '%s\n' "$n" | grep -c .)" = 1 ] || die "the release has no shared plasma-fusion package."
    DEBS=" $n" DEB_PARTIAL=1
  fi
}

# ---------- plan and channels ----------

plan() {
  case $LANE in
    copr)
      if [ -n "$DEV_DNF_REPO" ]; then
        echo "  sudo tee /etc/yum.repos.d/plasma-fusion-test.repo   (test repository $DEV_DNF_REPO)"
      else
        echo "  sudo dnf -y copr enable $REPO fedora-$FEDORA-x86_64"
      fi
      echo "  sudo dnf -y install $PKGS" ;;
    aur)
      if [ -n "$DEV_AUR_SRC" ]; then echo "  (cd $DEV_AUR_SRC && makepkg -si)   (test PKGBUILD)"
      elif has yay; then echo "  yay -S --needed $PKGS"
      elif has paru; then echo "  paru -S --needed $PKGS"
      fi ;;
    ppa)
      if [ -n "$DEV_APT_REPO" ]; then echo "  sudo tee /etc/apt/sources.list.d/plasma-fusion-test.list   (test repository)"
      else echo "  sudo add-apt-repository -y ppa:$REPO"; fi
      echo "  sudo apt-get update"
      echo "  sudo apt-get install -y $PKGS" ;;
    deb)
      echo "  download from $RELEASE_BASE:$DEBS (checked against the signed SHA256SUMS)"
      echo "  sudo apt-get install -y <those files>" ;;
  esac
  if [ "$PACKAGE_ONLY" = 1 ]; then
    echo "  then, as each user in their Plasma session: plasma-fusion setup"
  else
    echo "  plasma-fusion $SETUP_CMD$SETUP_FLAGS   (as you, in this session; it backs up first)"
  fi
}

install_packages() {
  case $LANE in
    copr)
      if [ -n "$DEV_DNF_REPO" ]; then
        printf '[plasma-fusion-test]\nname=Plasma Fusion test repository\nbaseurl=%s\ngpgcheck=0\nenabled=1\n' "$DEV_DNF_REPO" |
          $SUDO tee /etc/yum.repos.d/plasma-fusion-test.repo >/dev/null
      else
        has dnf && dnf copr --help >/dev/null 2>&1 || $SUDO dnf -y install dnf5-plugins || $SUDO dnf -y install dnf-plugins-core
        $SUDO dnf -y copr enable "$REPO" "fedora-$FEDORA-x86_64" || die "could not enable the Copr repository."
      fi
      # shellcheck disable=SC2086
      $SUDO dnf -y install $PKGS || die "dnf could not install Plasma Fusion." ;;
    aur)
      if [ -n "$DEV_AUR_SRC" ]; then
        (cd "$DEV_AUR_SRC" && makepkg -si --noconfirm) || die "makepkg failed."
      else
        # The helper asks its own questions (PKGBUILD review, sudo) on the terminal; --yes answers them.
        if [ "$YES" = 1 ]; then noconfirm=--noconfirm input=/dev/null; else noconfirm='' input=/dev/tty; fi
        if has yay; then
          # shellcheck disable=SC2086
          yay -S --needed $noconfirm $PKGS <"$input" || die "yay could not build Plasma Fusion."
        elif has paru; then
          # shellcheck disable=SC2086
          paru -S --needed $noconfirm $PKGS <"$input" || die "paru could not build Plasma Fusion."
        fi
      fi ;;
    ppa)
      if [ -n "$DEV_APT_REPO" ]; then
        printf '%s\n' "$DEV_APT_REPO" | $SUDO tee /etc/apt/sources.list.d/plasma-fusion-test.list >/dev/null
      else
        has add-apt-repository || die "add-apt-repository is missing: sudo apt-get install software-properties-common, then run this again."
        $SUDO add-apt-repository -y "ppa:$REPO" || die "could not add the PPA."
      fi
      $SUDO apt-get update || die "apt-get update failed."
      # shellcheck disable=SC2086
      $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y $PKGS || die "apt could not install Plasma Fusion." ;;
    deb)
      files=
      for n in $DEBS; do
        f=$(fetch_asset "$n") || exit 1
        files="$files $f"
      done
      # No downgrade: the shared package must be newer than or equal to the installed one.
      have=$(pf_installed plasma-fusion)
      new=$(dpkg-deb -f "$TMP/$(printf '%s\n' $DEBS | head -n 1)" Version)
      if [ -n "$have" ] && dpkg --compare-versions "$new" lt "$have"; then
        refuse "Plasma Fusion $have is installed, newer than this release's $new."
      fi
      # shellcheck disable=SC2086
      $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y $files || die "apt could not install the packages."
      [ "$DEB_PARTIAL" = 0 ] ||
        warn "this system has no build of the window decoration, settings page and tablet gestures; the themes, widgets and tools are installed." ;;
  esac
}

print_nix() {
  cat >&2 <<EOF
[plasma-fusion] NixOS: add Plasma Fusion to your system configuration (this installer never edits
it). With flakes, in flake.nix:

  inputs.plasma-fusion.url = "github:$REPO/v$PF_VERSION";
  inputs.plasma-fusion.inputs.nixpkgs.follows = "nixpkgs";
  # in nixosConfigurations.<host>.modules:
  plasma-fusion.nixosModules.default
  { programs.plasma-fusion.enable = true; }

Without flakes, as /etc/nixos/plasma-fusion.nix imported from configuration.nix:

  { ... }:
  let src = builtins.fetchGit { url = "https://github.com/$REPO"; ref = "refs/tags/v$PF_VERSION"; };
  in { imports = [ (src + "/packaging/nix/module.nix") ]; programs.plasma-fusion = { enable = true; inherit src; }; }

Then: sudo nixos-rebuild switch, and in your Plasma session: plasma-fusion setup
EOF
}

print_atomic() {
  cat >&2 <<EOF
[plasma-fusion] Fedora Atomic: layer the packages, reboot, then run this again in your Plasma
session for the setup step:

  sudo curl -fsSL -o /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:archledger:plasma-fusion.repo \\
    https://copr.fedorainfracloud.org/coprs/$REPO/repo/fedora-$(rpm -E %fedora 2>/dev/null)/archledger-plasma-fusion-fedora-$(rpm -E %fedora 2>/dev/null).repo
  rpm-ostree install $PKGS
  systemctl reboot
EOF
}

print_aur_steps() {
  cat >&2 <<EOF
[plasma-fusion] No AUR helper (yay or paru) was found. Build the package yourself:

  sudo pacman -S --needed base-devel git
  gpg --recv-keys $KEY_FP
  git clone https://aur.archlinux.org/plasma-fusion.git && cd plasma-fusion && makepkg -si

Then run this installer again in your Plasma session for the setup step.
EOF
}

consent() {
  [ "$YES" = 1 ] && return 0
  # In a subshell: on dash a failed redirection of a special builtin would end the script.
  if ! (: </dev/tty) 2>/dev/null; then
    die "no terminal to ask in: run it again with --yes to go ahead with the plan above."
  fi
  printf '[plasma-fusion] Go ahead? [y/N] ' >&2
  read -r answer </dev/tty || answer=
  case $answer in y | Y | yes | Yes) : ;; *) say "Declined; nothing was changed."; exit 4 ;; esac
}

status() {
  echo "system: $OS_PRETTY_NAME (channel: $LANE)"
  echo "Plasma: ${PLASMA:-not installed}${KWIN:+, KWin $KWIN}"
  for p in $PKGS; do
    v=$(pf_installed "$p")
    echo "  $p: ${v:-not installed}"
  done
  if has plasma-fusion; then plasma-fusion status; fi
}

main() {
  MODE=install YES=${PLASMA_FUSION_YES:-0} DRY=${PLASMA_FUSION_DRY_RUN:-0}
  PACKAGE_ONLY=${PLASMA_FUSION_PACKAGE_ONLY:-0} INSECURE=${PLASMA_FUSION_INSECURE_NO_SIG:-0} SETUP_FLAGS=
  while [ $# -gt 0 ]; do
    case $1 in
      install | update | uninstall | status) MODE=$1 ;;
      --yes | -y) YES=1 ;;
      --dry-run) DRY=1 ;;
      --package-only) PACKAGE_ONLY=1 ;;
      --insecure-no-sig) INSECURE=1 ;;
      --light | --dark | --auto | --no-auto | --keep-layout | --keep-shortcuts) SETUP_FLAGS="$SETUP_FLAGS $1" ;;
      -h | --help) sed -n '5,33p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//' >&2 || say "see docs/parts/installer.md"; exit 0 ;;
      *) say "unknown option: $1 (see --help)"; exit 2 ;;
    esac
    shift
  done

  # An unstamped copy (the repository's) runs only for tests, with the endpoints they give; a
  # release copy takes none of these from the environment.
  DEV_DNF_REPO='' DEV_APT_REPO='' DEV_AUR_SRC='' RELEASE_BASE='' TEST_ROOT=''
  case $PF_VERSION in
    @*)
      [ "${PLASMA_FUSION_DEV:-}" = 1 ] || refuse "this copy of the installer is not from a release: use the release URL (docs/parts/installer.md)."
      PF_VERSION=${PLASMA_FUSION_DEV_VERSION:?} PF_PLASMA_SERIES=${PLASMA_FUSION_DEV_SERIES:-6.7}
      PF_COPR_FEDORA=${PLASMA_FUSION_DEV_COPR_FEDORA:-44} PF_PPA_SERIES=${PLASMA_FUSION_DEV_PPA_SERIES:-stonking}
      PF_DEB_TARGETS=${PLASMA_FUSION_DEV_DEB_TARGETS:-neon testing}
      DEV_DNF_REPO=${PLASMA_FUSION_DEV_DNF_REPO:-} DEV_APT_REPO=${PLASMA_FUSION_DEV_APT_REPO:-}
      DEV_AUR_SRC=${PLASMA_FUSION_DEV_AUR_SRC:-} RELEASE_BASE=${PLASMA_FUSION_DEV_RELEASE_BASE:-}
      TEST_ROOT=${PLASMA_FUSION_DEV_ROOT:-}
      if [ -n "${PLASMA_FUSION_DEV_KEY:-}" ]; then
        KEY_ASC=$(cat "$PLASMA_FUSION_DEV_KEY") KEY_FP=${PLASMA_FUSION_DEV_KEY_FP:?}
      fi
      warn "test mode (unstamped installer, PLASMA_FUSION_DEV=1)" ;;
  esac
  RELEASE_BASE=${RELEASE_BASE:-https://github.com/$REPO/releases/download/v$PF_VERSION}

  [ "$(id -u)" != 0 ] || refuse "run it as your own user, not as root (or with sudo): it asks for sudo when it needs it."
  has curl || die "this installer needs curl."
  [ "$(uname -m)" = x86_64 ] || refuse "Plasma Fusion packages are built for x86-64 only for now."
  detect_lane
  say "Plasma Fusion $PF_VERSION installer on $OS_PRETTY_NAME"

  case $LANE in
    nix) check_plasma; print_nix; exit 0 ;;
    atomic) check_plasma; print_atomic; exit 0 ;;
  esac
  check_plasma
  if [ "$MODE" = status ]; then status; exit 0; fi

  installed=$(pf_installed plasma-fusion)
  case $MODE in
    install)
      if [ -n "$installed" ]; then
        say "Plasma Fusion $installed is already installed: use 'update' to update it, or 'plasma-fusion setup' for your account."
        exit 0
      fi
      SETUP_CMD=setup ;;
    update)
      [ -n "$installed" ] || refuse "Plasma Fusion is not installed (use install)."
      [ -z "$SETUP_FLAGS" ] || refuse "update keeps your choices and takes no setup options."
      SETUP_CMD=update ;;
    uninstall)
      [ -n "$installed" ] || { say "Plasma Fusion is not installed; nothing to do."; exit 0; } ;;
  esac
  check_session

  TMP=$(mktemp -d) || die "cannot make a temporary directory."
  trap 'rm -rf "$TMP"' EXIT INT TERM
  SUDO=sudo
  has sudo || die "this installer needs sudo for the package step."

  if [ "$MODE" = uninstall ]; then
    say "Plan:"
    [ "$PACKAGE_ONLY" = 1 ] || echo "  plasma-fusion restore   (your desktop as it was before Plasma Fusion)" >&2
    case $LANE in
      copr) echo "  sudo dnf -y remove $PKGS" >&2 ;;
      aur) echo "  sudo pacman -Rns $PKGS plasma-fusion-debug (the ones installed)" >&2 ;;
      ppa | deb) echo "  sudo apt-get remove -y $PKGS" >&2 ;;
    esac
    [ "$DRY" = 1 ] && { say "Dry run: nothing was changed."; exit 0; }
    consent
    if [ "$PACKAGE_ONLY" = 0 ] && has plasma-fusion; then
      plasma-fusion restore </dev/null || die "restoring your desktop stopped; the packages stay installed."
    fi
    $SUDO -v || die "sudo failed."
    installed_pkgs=
    # An AUR helper also installs the debug package makepkg builds by default; pacman does not
    # remove it with the others (dnf and apt remove their debug packages as dependents).
    all_pkgs=$PKGS
    [ "$LANE" = aur ] && all_pkgs="$PKGS plasma-fusion-debug"
    for p in $all_pkgs; do [ -z "$(pf_installed "$p")" ] || installed_pkgs="$installed_pkgs $p"; done
    # shellcheck disable=SC2086 # package lists split on purpose
    case $LANE in
      copr) $SUDO dnf -y remove $installed_pkgs ;;
      aur) $SUDO pacman -Rns --noconfirm $installed_pkgs ;;
      ppa | deb) $SUDO env DEBIAN_FRONTEND=noninteractive apt-get remove -y $installed_pkgs ;;
    esac || die "the package removal failed."
    say "Plasma Fusion was removed. Log out and in once."
    exit 0
  fi

  if [ "$LANE" = aur ] && [ -z "$DEV_AUR_SRC" ] && ! has yay && ! has paru; then
    print_aur_steps
    exit 3
  fi
  [ "$LANE" != deb ] || deb_assets
  say "Plan:"
  plan >&2
  [ "$DRY" = 1 ] && { say "Dry run: nothing was changed."; exit 0; }
  consent
  $SUDO -v || die "sudo failed."
  if [ "$MODE" = update ]; then
    say "updating the packages"
    # shellcheck disable=SC2086 # package lists split on purpose
    case $LANE in
      copr) $SUDO dnf -y upgrade --refresh $PKGS || die "dnf could not update Plasma Fusion." ;;
      aur) install_packages ;;
      ppa) { $SUDO apt-get update && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade $PKGS; } || die "apt could not update Plasma Fusion." ;;
      deb) install_packages ;;
    esac
  else
    say "installing the packages"
    install_packages
  fi
  has plasma-fusion || die "the packages were installed but the plasma-fusion command is missing."
  say "installed: Plasma Fusion $(plasma-fusion version)"
  if [ "$PACKAGE_ONLY" = 1 ]; then
    say "Now, as each user in their Plasma session: plasma-fusion setup"
    exit 0
  fi
  # shellcheck disable=SC2086
  plasma-fusion "$SETUP_CMD" $SETUP_FLAGS </dev/null ||
    die "the setup stopped; your previous desktop is in the backup: plasma-fusion restore --latest"
  say "Done. Log out and back in once."
  say "Optional: the login screen (sudo /usr/share/plasma-fusion/tools/system/greeter-apply.sh) and, on Fedora, the boot splash (sudo /usr/share/plasma-fusion/tools/system/plymouth-install.sh)."
}

# Runs only once the whole script has been read: a truncated download does nothing.
main "$@"
