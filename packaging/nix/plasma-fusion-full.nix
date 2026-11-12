# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The Plasma Fusion full profile for NixOS: the six packages with the fork's KWin pinned.
# Used by ./module.nix's full-profile option. The fork replaces the stock kdePackages.kwin
# for this system only (Nix's purity makes the pin natural — the stock packages are untouched).
#
#   pkgs:         a nixpkgs package set
#   plasmaFusion: the plasma-fusion flake's packages (plasma-fusion, -decoration, etc.)
#   kwinFusion:   the fork's KWin derivation (from ./kwin-fusion.nix)
{ pkgs, plasmaFusion, kwinFusion }:

let
  inherit (pkgs) lib;

  # The profile's packages: the six Plasma Fusion packages and the fork's KWin.
  packages = [
    plasmaFusion.plasma-fusion
    plasmaFusion.plasma-fusion-decoration
    plasmaFusion.plasma-fusion-settings
    plasmaFusion.plasma-fusion-navigation
    plasmaFusion.plasma-fusion-quicklook
    plasmaFusion.plasma-fusion-copytext
    kwinFusion
  ];

  # The metapackage: its output links every package of the profile, so its closure is the
  # profile — installing it installs the set, and the module links this one path.
  plasma-fusion-full = pkgs.symlinkJoin {
    name = "plasma-fusion-full-${plasmaFusion.plasma-fusion.version}";
    paths = packages;
    postBuild = ''
      mkdir -p "$out/share/doc/plasma-fusion-full"
      cat > "$out/share/doc/plasma-fusion-full/PROFILE" <<EOF
      profile=full
      kwin=${kwinFusion.version}
      plasma-fusion=${plasmaFusion.plasma-fusion.version}
      EOF
    '';
    meta = {
      description = "The Plasma Fusion full profile: the desktop with the pinned KWin fork";
      homepage = "https://github.com/archledger/plasma-fusion";
    };
  };
in
{
  inherit plasma-fusion-full;

  # What the module links into environment.systemPackages when the full profile is enabled:
  # the metapackage alone (its closure carries the whole set).
  systemPackages = [ plasma-fusion-full ];
}
