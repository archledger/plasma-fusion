# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The Plasma Fusion full profile for NixOS: the six packages with the fork's KWin pinned.
# Used by ./module.nix's full-profile option. The fork is an overlay override of kdePackages.kwin
# (Nix's purity makes the pin natural — the system's Plasma Fusion KWin replaces the stock one
# for this system only, and the stock packages are untouched).
#
#   pkgs:  a nixpkgs package set
#   plasmaFusion: the plasma-fusion flake's packages (plasma-fusion, -decoration, etc.)
#   kwinFusion: the fork's KWin derivation (from ./kwin-fusion.nix)
{ pkgs, plasmaFusion, kwinFusion }:

let
  inherit (pkgs) lib;
in
{
  # The metapackage: the six Plasma Fusion packages with the fork's KWin.
  # A Nix metapackage is a symlink tree of its dependencies.
  plasma-fusion-full = pkgs.runCommand "plasma-fusion-full" {
    meta = {
      description = "The Plasma Fusion full profile: the desktop with the pinned KWin fork";
      homepage = "https://github.com/archledger/plasma-fusion";
    };
  } ''
    mkdir -p $out/share/doc/plasma-fusion-full
    cat > $out/share/doc/plasma-fusion-full/PROFILE <<EOF
    profile=full
    kwin=${kwinFusion.version}
    plasma-fusion=${plasmaFusion.plasma-fusion.version}
    EOF
  '';

  # The system packages to link: the six + the fork's KWin (replacing stock).
  # Used by the module's environment.systemPackages when the full profile is enabled.
  systemPackages = [
    plasmaFusion.plasma-fusion
    plasmaFusion.plasma-fusion-decoration
    plasmaFusion.plasma-fusion-settings
    plasmaFusion.plasma-fusion-navigation
    plasmaFusion.plasma-fusion-quicklook
    plasmaFusion.plasma-fusion-copytext
    kwinFusion
  ];
}
