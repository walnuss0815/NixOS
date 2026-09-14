# walnuss0815 NixOS

## Initial Setup (New Host)

For hosts using disko + LUKS2 + TPM2 + Secure Boot (see `hosts/owhug-pc1`
for a full example), follow this runbook:

1. **(Dual-boot with Windows only)** In Windows, suspend BitLocker
   protection and save/print the recovery key. Do this before touching
   Secure Boot state at all — enrolling new Secure Boot keys changes
   the firmware's Secure Boot state (PCR 7), which invalidates
   BitLocker's TPM-sealed unlock otherwise.
2. Enter BIOS/UEFI setup: confirm UEFI-only boot (no CSM/legacy), and
   if Secure Boot isn't already in "Setup Mode", clear its keys to
   enter it.
3. Boot the NixOS installer. Identify the target disk with
   `ls -l /dev/disk/by-id/` — always use the stable by-id path, never
   `/dev/nvmeXn1` (not guaranteed stable across reboots). On a
   multi-disk system, double-check you've picked the right one; this
   step is destructive.
4. Partition, format, mount and install in one step:

   ```bash
   sudo nix run 'github:nix-community/disko/v1.13.0#disko-install' -- \
     --write-efi-boot-entries \
     --flake '.#<hostname>' \
     --disk main /dev/disk/by-id/<the-real-disk-id>
   ```

   `--write-efi-boot-entries` registers a firmware boot entry; omit it
   only for a portable/USB install.
5. First boot: unlock with the LUKS passphrase, then enroll a TPM2
   keyslot so future boots unlock automatically:

   ```bash
   sudo systemd-cryptenroll --tpm2-device=auto <device>
   ```

   The passphrase keyslot is never removed and remains as a fallback.
6. Reboot to firmware, enable Secure Boot. Reboot into NixOS to let
   lanzaboote auto-enroll its keys. Verify with `sbctl status` /
   `sbctl verify`.
7. **(Dual-boot with Windows only)** Boot into Windows via the firmware
   boot menu to confirm it still boots under the newly-enrolled Secure
   Boot key set.
8. **(Dual-boot with Windows only)** In Windows, resume BitLocker
   protection — this reseals its keys against the new, now-stable
   Secure Boot state.

See the runbook comment at the top of each host's `configuration.nix`
for any host-specific caveats.

## Disko

Hosts with a `hosts/<host>/disko.nix` file use
[disko](https://github.com/nix-community/disko) for declarative disk
partitioning. Disko generates `fileSystems` and, for encrypted hosts,
`boot.initrd.luks.devices` automatically from that file — these options
must not also be hand-written in `configuration.nix` /
`hardware-configuration.nix` for those hosts, or NixOS will raise a
conflicting-definition error.

- Fresh install: see [Initial Setup](#initial-setup-new-host) above.
- Mount an already-formatted disk matching the disko config (e.g. to
  repair or rebuild an existing install without wiping data): see the
  `--mode mount` option in the [disko
  reference](https://github.com/nix-community/disko/blob/master/docs/reference.md).

## Build System

```bash
sudo nixos-rebuild switch --flake .#alexander-nb2
```

## Build Home

```bash
home-manager switch --flake .#alexander
```

## Update Flake

```bash
nix flake update
```
