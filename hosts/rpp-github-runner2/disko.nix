# Declarative disk layout, applied by nixos-anywhere during install (see
# ./README.md). disko generates fileSystems."/" and
# boot.loader.grub.devices from this file; do not also hand-write them.
#
# A VM disk: no encryption (the VM holds no data worth protecting at rest
# and must boot unattended) and no ESP (legacy BIOS boot).
{
  disko.devices = {
    disk = {
      main = {
        # First disk on the VirtIO SCSI controller.
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # BIOS boot partition for GRUB
            };
            root = {
              size = "100%";
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
}
