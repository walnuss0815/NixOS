# PLACEHOLDER — this host has not been installed yet.
#
# Once NixOS is actually installed on owhug-pc1 (see the runbook comment
# at the top of ./configuration.nix), replace this file with the output
# of `nixos-generate-config --no-filesystems --root /mnt` (the
# `--no-filesystems` flag is important: disk-level filesystems, the ESP
# and the LUKS device are all managed declaratively by ./disko.nix
# instead, and must not be hand-written here too — doing so would
# conflict with disko's generated definitions). Re-apply the one
# hand-written addition below that nixos-generate-config won't restore:
#
#   - swapDevices with a `size`, sized to match installed RAM (see
#     configuration.nix's zramSwap comment)
#
# hardware.cpu.amd.updateMicrocode below is also provided by the
# nixos-hardware common-cpu-amd module in flake.nix — nixos-generate-config
# will add it here too, which is a harmless duplicate.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # Swapfile on the ext4 root (see ./disko.nix), created automatically by
  # NixOS during activation at the given size; zram (see configuration.nix)
  # is the fast primary swap, this is an OOM safety net / future
  # hibernation headroom.
  swapDevices = [
    { device = "/swapfile"; size = 32 * 1024; } # MiB — keep in sync with installed RAM
  ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
