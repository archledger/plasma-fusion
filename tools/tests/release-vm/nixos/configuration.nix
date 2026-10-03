# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The release-test NixOS VM (nixos/build-image.sh fills in @PUBKEY@, the test key of vm.sh).
{ pkgs, modulesPath, ... }:
{
  # The test runs under QEMU (virtio disk and network in the initrd).
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  services.desktopManager.plasma6.enable = true;
  # Mesa's drivers in /run/opengl-driver: a display manager's module would turn this on; the test logs in on
  # tty1 without one, and KWin found no usable DRM device.
  hardware.graphics.enable = true;
  programs.plasma-fusion.enable = true;
  environment.systemPackages = [ pkgs.kdePackages.konsole ];
  users.users.pf = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "@PUBKEY@" ];
  };
  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  # pf logs in on tty1 and starts a Plasma Wayland session there (no display manager), as in the
  # other release-test VMs.
  services.getty.autologinUser = "pf";
  programs.bash.loginShellInit = ''
    if [ "$(tty)" = /dev/tty1 ] && [ -z "''${WAYLAND_DISPLAY:-}" ] && [ "$USER" = pf ]; then
      exec startplasma-wayland >"$HOME/.plasma-tty1.log" 2>&1
    fi
  '';
  environment.etc."xdg/kscreenlockerrc".text = "[Daemon]\nAutolock=false\nLockOnResume=false\nTimeout=0\n";
  networking.hostName = "pf-nixos";
  system.stateVersion = "26.05";
}
