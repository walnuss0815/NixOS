# Hardware configuration for alexander-pc2. Matches the output of
# `nixos-generate-config --no-filesystems --show-hardware-config` on this
# machine; re-run it and compare after hardware changes.
#
# Disk-level filesystems, the ESP and the LUKS device are managed
# declaratively by ./disko.nix and must not be hand-written here too.
# The one hand-written addition nixos-generate-config won't produce is
# swapDevices with a `size`, sized to match installed RAM.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # Swapfile on the ext4 root (see ./disko.nix), created automatically by
  # NixOS during activation at the given size; zram (see configuration.nix)
  # is the fast primary swap, this is an OOM safety net.
  swapDevices = [
    {
      device = "/swapfile";
      size = 64 * 1024;
    } # MiB — keep in sync with installed RAM
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
