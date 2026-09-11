# PLACEHOLDER — this host has not been installed yet.
#
# Once NixOS is actually installed on owhug-pc1 (see the runbook comment
# at the top of ./configuration.nix), replace this entire file with the
# output of `nixos-generate-config --root /mnt`, then re-apply the two
# hand-written additions below (nixos-generate-config won't know about
# the LUKS UUID or the swapfile by itself):
#
#   - the LUKS-unlocked device UUID for fileSystems."/" and the vfat ESP
#     UUID for fileSystems."/boot"
#   - swapDevices pointing at the swapfile created on the ext4 root
#     (see configuration.nix's zramSwap / runbook comment)
#   - hardware.cpu.amd.updateMicrocode (also provided by the
#     nixos-hardware common-cpu-amd module in flake.nix, but
#     nixos-generate-config will add it here too — harmless duplicate)
#
# The values below are placeholders so the flake evaluates; they are NOT
# real UUIDs and this host will not boot until this file is regenerated.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # TODO: replace with the real LUKS-unlocked root filesystem UUID.
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/REPLACE-ME-AFTER-INSTALL";
    fsType = "ext4";
  };

  # TODO: replace with the real ESP UUID (vfat, on the same NVMe drive).
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/REPLACE-ME-AFTER-INSTALL";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # Swapfile on the ext4 root, sized to match RAM, created after install
  # (`dd`/`fallocate` + `mkswap`) as an OOM safety net / future
  # hibernation headroom; zram (see configuration.nix) is the fast
  # primary swap.
  swapDevices = [
    { device = "/swapfile"; }
  ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
