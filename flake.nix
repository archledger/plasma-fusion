# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion for NixOS (docs/parts/nixos.md): the packages built from this tree, and a NixOS
# module whose source defaults to it.
#
#   inputs.plasma-fusion.url = "github:archledger/plasma-fusion/<tag>";
#   inputs.plasma-fusion.inputs.nixpkgs.follows = "nixpkgs";
#   modules = [ plasma-fusion.nixosModules.default { programs.plasma-fusion.enable = true; } ];
#
# Plasma 6.7 or later is needed (nixos-unstable until a NixOS release has it); the module stops the
# rebuild on an older Plasma.
{
  description = "Plasma Fusion: a KDE Plasma 6 desktop (themes, widgets, icons, fonts and setup tools)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      packagesFor = pkgs: import ./packaging/nix/plasma-fusion.nix { inherit pkgs; src = self; };
    in
    {
      packages = forAllSystems (pkgs:
        let pf = packagesFor pkgs; in
        {
          inherit (pf) plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation;
          default = pf.plasma-fusion;
        });

      nixosModules.default = { lib, ... }: {
        imports = [ ./packaging/nix/module.nix ];
        programs.plasma-fusion.src = lib.mkDefault self;
      };

      # nix flake check builds the four packages.
      checks = forAllSystems (pkgs: removeAttrs (packagesFor pkgs) [ "override" "overrideDerivation" ]);
    };
}
