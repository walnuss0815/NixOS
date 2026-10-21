# Declarative disk layout for alexander-pc2, applied by nixos-anywhere
# during install (see ./README.md). disko generates fileSystems."/",
# fileSystems."/boot" and boot.initrd.luks.devices.cryptroot
# automatically from this file — do not also hand-write those options in
# configuration.nix / hardware-configuration.nix, or NixOS will raise a
# conflicting-definition error.
#
# The host has a single NVMe drive that is used entirely by NixOS:
# 1G ESP, the rest LUKS2 with ext4 inside.
{
  disko.devices = {
    disk = {
      main = {
        # The only disk in this machine, so the kernel name is
        # unambiguous. Only used when formatting (install); the installed
        # system mounts by partition label.
        device = "/dev/nvme0n1";
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
                mountOptions = [
                  "fmask=0022"
                  "dmask=0022"
                ];
              };
            };
            cryptroot = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                # Initial LUKS passphrase, only read while formatting.
                # nixos-anywhere copies it here from the machine running
                # the install (`--disk-encryption-keys /tmp/secret.key
                # <local-file>`, see ./README.md); it is not part of the
                # installed system.
                passwordFile = "/tmp/secret.key";
                settings = {
                  # SSD TRIM passthrough for the common-pc-ssd fstrim timer
                  # (flake.nix) to reach the NVMe device through the LUKS
                  # mapper. Trade-off: leaks the free-space pattern to
                  # someone with physical disk access; accepted for NVMe
                  # performance/endurance.
                  allowDiscards = true;
                  # TPM2 auto-unlock once a TPM2 keyslot has been enrolled
                  # (see ./README.md). Required for this headless host to
                  # come back up unattended after (auto-upgrade) reboots.
                  # Harmless no-op until that keyslot exists; the
                  # passphrase keyslot remains as a fallback.
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
