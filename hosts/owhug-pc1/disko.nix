# Declarative disk layout for owhug-pc1, applied via disko (see the
# install runbook at the top of ./configuration.nix). disko generates
# fileSystems."/", fileSystems."/boot" and boot.initrd.luks.devices.cryptroot
# automatically from this file — do not also hand-write those options in
# configuration.nix / hardware-configuration.nix, or NixOS will raise a
# conflicting-definition error.
#
# IMPORTANT: this targets ONLY the dedicated second NVMe drive for NixOS —
# the Windows/BitLocker drive must never be touched. Identify the correct
# by-id path with `ls -l /dev/disk/by-id/` before installing; by-id paths
# are stable across reboots/reordering, unlike /dev/nvmeXn1 numbering.
#
# Install with disko-install (partitions + formats + nixos-installs in one
# step, and registers a firmware boot entry so the OS shows up in the F8
# boot menu):
#
#   sudo nix run 'github:nix-community/disko/v1.13.0#disko-install' -- \
#     --write-efi-boot-entries \
#     --flake '.#owhug-pc1' \
#     --disk main /dev/disk/by-id/<the-real-nvme-id>
#
# --write-efi-boot-entries is required here: by default disko-install
# targets portable/USB installs and won't register an NVRAM boot entry
# on its own. See docs:
# https://github.com/nix-community/disko/blob/master/docs/disko-install.md
{
  disko.devices = {
    disk = {
      main = {
        # Overridden by `--disk main <device>` when using disko-install
        # (recommended, see above). Only matters if invoking the plain
        # `disko` script directly instead.
        device = "/dev/disk/by-id/REPLACE-ME-AFTER-INSTALL";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "fmask=0022" "dmask=0022" ];
              };
            };
            cryptroot = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                settings = {
                  # SSD TRIM passthrough for the common-pc-ssd fstrim timer
                  # (flake.nix) to actually reach the underlying NVMe device
                  # through the LUKS mapper. Trade-off: this can let an
                  # attacker with physical disk access infer which blocks
                  # are in use from the free-space pattern — accepted here
                  # for sustained NVMe performance/endurance on a personal
                  # desktop.
                  allowDiscards = true;
                  # Allow the TPM2 chip to auto-unlock this volume once a
                  # TPM2 keyslot has been enrolled via
                  # `systemd-cryptenroll --tpm2-device=auto` (see runbook
                  # step 5). Harmless no-op until that keyslot exists; the
                  # original passphrase keyslot remains as a fallback.
                  crypttabExtraOpts = [ "tpm2-device=auto" ];
                };
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };
    };
  };
}
