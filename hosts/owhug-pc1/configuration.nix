# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').
#
# ---------------------------------------------------------------------------
# owhug-pc1 — install / dual-boot runbook
# ---------------------------------------------------------------------------
# Dual boot with an already-installed Windows system that lives
# on its own, separate NVMe drive with BitLocker enabled. NixOS gets its own
# dedicated second NVMe drive — no shared ESP, no partition resizing needed.
#
# Secure Boot's PK/KEK/db key database is firmware-wide (shared across both
# drives, not per-disk), and BitLocker's TPM auto-unlock is normally sealed
# against PCR 7 (Secure Boot state). Enrolling lanzaboote's custom keys
# changes PCR 7, which WILL invalidate BitLocker's TPM seal unless handled
# in the order below.
#
# 1. In Windows: suspend BitLocker protection (Settings, or
#    `manage-bde -protectors -disable C:`) and save/print the recovery key.
#    Do this before touching Secure Boot state at all.
# 2. Enter BIOS/UEFI setup: confirm UEFI-only boot (no CSM/legacy), and
#    put Secure Boot into "Setup Mode" (clear existing keys) if required.
# 3. Boot the NixOS installer. Partition ONLY the new/second NVMe drive —
#    the Windows drive is left completely untouched:
#      - ESP: ~1GB, vfat, mounted at /boot
#      - Rest of the drive: one LUKS2 container ("cryptroot")
#    Inside the LUKS container, format ext4 and mount at /.
#    After the first boot, create a swapfile on the ext4 root sized to
#    match RAM as an OOM safety net / future hibernation headroom; zram
#    (enabled below) is the fast primary swap.
# 4. `nixos-generate-config --root /mnt`, then merge the LUKS UUID and any
#    detected kernel modules into hardware-configuration.nix. Copy this
#    file into place as configuration.nix. `nixos-install`.
# 5. First boot: unlock with the LUKS passphrase, then enroll the TPM2
#    keyslot: `systemd-cryptenroll --tpm2-device=auto /dev/nvme<X>n1p2`
#    (the passphrase keyslot remains as a fallback).
# 6. Reboot to firmware, enable Secure Boot. Reboot into NixOS to let
#    lanzaboote auto-enroll its keys (see boot.lanzaboote below). Verify
#    with `sbctl status` / `sbctl verify`.
# 7. Boot into Windows via the firmware boot menu (F8) to confirm it still
#    boots under the newly-enrolled Secure Boot key set (Windows Boot
#    Manager stays trusted because of includeMicrosoftKeys below).
# 8. In Windows: resume BitLocker protection. This reseals its keys
#    against the new, now-stable PCR7 value.
#
# OS selection happens at the firmware boot menu (F8), since each drive has
# its own ESP — there is no unified systemd-boot menu across both disks.
# ---------------------------------------------------------------------------

{ config, lib, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  # Lanzaboote replaces the systemd-boot module for Secure Boot signing
  # (see boot.lanzaboote below), so it must be force-disabled here.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Secure Boot: generates its own keys on first activation and stages
  # them on the ESP for firmware auto-enrollment (systemd-boot's native
  # "Enroll SecureBoot keys" support). After the next `nixos-rebuild
  # switch`, reboot into firmware and enable Secure Boot, then reboot
  # again to let it auto-enroll. Use `sbctl status`/`sbctl verify` to
  # check progress. includeMicrosoftKeys is required here so the
  # Windows Boot Manager on the other drive stays trusted (see runbook
  # above — Secure Boot keys are shared across all drives).
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    autoGenerateKeys.enable = true;
    autoEnrollKeys = {
      enable = true;
      includeMicrosoftKeys = true; # keep Windows Boot Manager / BitLocker-signed OS bootable
      autoReboot = false; # we control when the finalizing reboot happens
    };
  };

  # Required for TPM2-bound LUKS auto-unlock (crypttabExtraOpts below).
  boot.initrd.systemd.enable = true;

  # Udev rules for TPM2 device access (tpm2-tools, systemd-cryptenroll).
  security.tpm2.enable = true;

  boot.initrd.luks.devices = {
    cryptroot = {
      # TODO: replace with the real LUKS partition UUID after install
      # (see runbook step 4 above).
      device = "/dev/disk/by-uuid/REPLACE-ME-AFTER-INSTALL";
      # Allow the TPM2 chip to auto-unlock this volume once a TPM2 keyslot
      # has been enrolled via `systemd-cryptenroll --tpm2-device=auto`.
      # The original passphrase keyslot remains as a fallback.
      crypttabExtraOpts = [ "tpm2-device=auto" ];
    };
  };

  networking.hostName = "owhug-pc1"; # Define your hostname.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager = {
    enable = true;
  };

  # Bluetooth
  hardware.bluetooth.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Desktop/GUI applications (LibreOffice, browsers, chat, media) live in
  # home-manager (users/alexander/default.nix) instead: per-user apps
  # don't need a full `sudo nixos-rebuild switch` to add/remove/update, and
  # this keeps the system closure limited to what's actually needed
  # system-wide, consistent with the modules/system vs modules/user split
  # used elsewhere in this repo.
  environment.systemPackages = with pkgs; [
    # Tools
    git
    git-credential-oauth
    vim
    wget
    curl

    # Nix Home Manager
    home-manager

    # VM
    qemu

    # Secure Boot key management / troubleshooting (see boot.lanzaboote)
    sbctl

    # TPM2 troubleshooting (see boot.initrd.luks.devices.cryptroot)
    tpm2-tools
  ];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "de";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable firmware update tool
  services.fwupd.enable = true;

  # Enable sound with pipewire.
  hardware.alsa.enablePersistence = true;
  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.alexander = {
    isNormalUser = true;
    description = "Alexander Weidemann";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "dialout" "netbird-personal" "video" ];
    shell = pkgs.zsh;
    packages = with pkgs; [ ];
  };

  # Automatic login is disabled; GDM always prompts.
  services.displayManager.autoLogin.enable = false;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  programs.zsh.enable = true;

  # NVIDIA GPU: recent generations require the open kernel module —
  # the closed-source module does not support current hardware.
  # services.xserver.videoDrivers is set to [ "nvidia" ] via the
  # nixos-hardware common-gpu-nvidia-nonprime module in flake.nix.
  hardware.nvidia = {
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.production;
    nvidiaSettings = true;
  };
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Latest Linux kernel (needed for current-gen CPU/GPU driver support).
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # zram as fast primary swap; a disk-backed swapfile on the ext4 root
  # (see hardware-configuration.nix) acts as an additional OOM safety
  # net / future hibernation headroom.
  zramSwap.enable = true;

  # Enable flatpak
  services.flatpak.enable = true;

  virtualisation = {
    libvirtd = {
      enable = true;
    };
  };

  networking.resolvconf.enable = false;
  services.resolved.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
