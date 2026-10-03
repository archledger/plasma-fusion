# Part: NixOS

Plasma Fusion on NixOS through a Nix package and a NixOS module in `packaging/nix/`: the shared
part (what `tools/build.sh` stages) and the three compiled parts, built from the system's own
`kdePackages`, so every `nixos-rebuild` builds them against the KWin it ships.

## Requirements

Plasma 6.7 or later. NixOS 26.05 ships Plasma 6.6.6, which the compiled parts and several widgets
do not support (`find_package(KWin 6.7)`; 6.7-only QML interfaces), so until a NixOS release has
6.7 the system follows `nixos-unstable` (Plasma 6.7.5, KDE Frameworks 6.30, Qt 6.11.2 on
2026-10-02). The module stops the rebuild with a message on an older Plasma.

## Files

| File | What |
|---|---|
| `packaging/nix/plasma-fusion.nix` | `{ pkgs, src, version }` → `plasma-fusion` (the shared part), `plasma-fusion-decoration`, `plasma-fusion-settings`, `plasma-fusion-navigation` |
| `packaging/nix/module.nix` | `programs.plasma-fusion = { enable; src; compiledParts; plymouth; }` |

The shared package is installed by `packaging/install-tree.sh`, as on every channel
(system.md): the same files under `$out/share`, `$out/libexec/plasma-fusion` and
`$out/bin/plasma-fusion`, with the paths set for NixOS: the charge limit's polkit action and the
quick settings tile name the helper's store path (pkexec matches the action's `exec.path`), the
icon names handed back to Breeze and hicolor and the on-screen keyboard's desktop file point into
`/run/current-system/sw/share`, and the Plymouth theme names its store path. All four packages take
their version from `VERSION`. The per-user
templates (`share/plasma-fusion/config`) and the setup scripts (`share/plasma-fusion/tools`) come
along; `fusion-config.sh` finds the templates through `XDG_DATA_DIRS`, and the helpers through
`/run/current-system/sw/libexec/plasma-fusion` (`environment.pathsToLink`). The user services'
`ExecSearchPath` already lists that directory, and the login check reads the versions from the
system closure (`nix-store`, [`gate.md`](gate.md)). The helpers get the programs they run in
their PATH (on Fedora all in `/usr/bin`): power tiers gdbus, busctl and kwriteconfig6, app icons
rsvg-convert and busctl, and the charge limit coreutils, grep and systemctl, since pkexec starts it
with a PATH of `/usr/bin` and `/bin` only. The package brings its own Python (with Pillow, for the
app icons tool): the Python helpers and tools point to it, and the `plasma-fusion` command,
`fusion-config.sh`, `fusion-restore.sh` and `lockscreen-enable.sh` have it on their PATH, so a
system without a system-wide Python can run setup; the module also installs notify-send and gdbus for the
login check's notification. KDE Connect is optional: without it the quick settings leave the phone
tile out.

## Install

With flakes, add the input and the module (pin a tag once releases exist):

```nix
{
  inputs.plasma-fusion.url = "github:archledger/plasma-fusion";
  inputs.plasma-fusion.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, plasma-fusion, ... }: {
    nixosConfigurations.<host> = nixpkgs.lib.nixosSystem {
      modules = [
        ./configuration.nix
        plasma-fusion.nixosModules.default
        { programs.plasma-fusion.enable = true; }
      ];
    };
  };
}
```

`flake.nix` also offers the packages (`packages.<system>.{plasma-fusion, plasma-fusion-decoration,
plasma-fusion-settings, plasma-fusion-navigation}`), and `nix flake check` builds them. Its own
`nixpkgs` input follows nixos-unstable; with `follows` the system's nixpkgs is used instead.

Without flakes, in the system configuration, for example `/etc/nixos/plasma-fusion.nix` imported from
`configuration.nix`, with the source pinned to a commit:

```nix
{ ... }:
let
  plasma-fusion-src = builtins.fetchGit {
    url = "https://github.com/archledger/plasma-fusion";
    ref = "main";
    rev = "<commit>";
  };
in
{
  imports = [ (plasma-fusion-src + "/packaging/nix/module.nix") ];
  programs.plasma-fusion = { enable = true; src = plasma-fusion-src; };
}
```

Then `sudo nixos-rebuild switch`, and as each user, inside the Plasma session (it takes a backup
first and prints the undo command): `plasma-fusion setup`.

Log out and in once. To update, move `rev` to a newer commit and rebuild; to remove, undo the
per-user step with `plasma-fusion restore`, drop the import and rebuild (or boot the previous
generation).

## Not covered yet

- The boot splash (`plymouth = true`) is built but not tried on a real NixOS boot.
- The login greeter styling (`tools/system/greeter-apply.sh`) assumes plasma-login-manager; NixOS
  uses SDDM.
