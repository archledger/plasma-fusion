# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The release-test NixOS VM image from a Plasma Fusion source tree (@SRC@, nixos/build-image.sh).
{
  description = "Plasma Fusion release test: a NixOS VM image";
  inputs.plasma-fusion.url = "@SRC@";
  # The nixos-unstable revision Plasma Fusion's flake.lock pins.
  inputs.nixpkgs.follows = "plasma-fusion/nixpkgs";
  outputs = { nixpkgs, plasma-fusion, ... }: {
    nixosConfigurations.pftest = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ plasma-fusion.nixosModules.default ./configuration.nix ];
    };
  };
}
