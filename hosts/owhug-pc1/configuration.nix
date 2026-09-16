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
# 2. Enter BIOS/UEFI setup: confirm UEFI-only boot (no CSM/legacy), put
#    Secure Boot into "Setup Mode" (clear existing keys) if required,
#    and confirm AMD fTPM/PSP is enabled (often labelled "AMD fTPM
#    switch" or "PSP fTPM") — required for step 5's TPM2 enrollment.
# 3. Boot the NixOS installer. Identify the target drive with
#    `ls -l /dev/disk/by-id/` — pick the by-id path for the new/second
#    NVMe drive. Double check it, since the next step is destructive and
#    the Windows/BitLocker drive must never be touched.
# 4. Partition, format, mount and install in one step via disko-install
#    (see ./disko.nix for the declarative layout):
#      sudo nix run 'github:nix-community/disko/v1.13.0#disko-install' -- \
#        --write-efi-boot-entries \
#        --flake '.#owhug-pc1' \
#        --disk main /dev/disk/by-id/<the-real-nvme-id>
#    --write-efi-boot-entries is required so the new install actually
#    registers a firmware (F8) boot entry — disko-install otherwise
#    assumes a portable/USB install and skips NVRAM changes.
# 5. First boot: unlock with the LUKS passphrase, then enroll the TPM2
#    keyslot against the same device disko uses for cryptroot (see
#    ./disko.nix — NOT the whole-disk by-id path from step 3/4):
#      systemd-cryptenroll --tpm2-device=auto /dev/disk/by-partlabel/disk-main-cryptroot
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
    # Declarative disk layout; generates fileSystems."/",
    # fileSystems."/boot" and boot.initrd.luks.devices.cryptroot.
    ./disko.nix
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

  # Required for TPM2-bound LUKS auto-unlock (crypttabExtraOpts, set via
  # ./disko.nix's cryptroot settings).
  boot.initrd.systemd.enable = true;

  # Udev rules for TPM2 device access (tpm2-tools and other unprivileged
  # tooling; systemd-cryptenroll itself runs as root and doesn't
  # strictly require this, but it's harmless to keep enabled).
  security.tpm2.enable = true;

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

    # TPM2 troubleshooting (see ./disko.nix's cryptroot settings)
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

  # Local LLM: NInfer serving Qwen3.8-27B (NVFP4 + Vision + DFlash2). See
  # ./NINFER-SETUP.md for the one-time, GPU-bound model conversion this
  # depends on (not expressible as a Nix derivation - downloads ~80GB of
  # upstream checkpoints and runs upstream's own conversion tooling) and for
  # generating apiKeyFile's contents.
  #
  # "LAN + API key" exposure: bound to all interfaces and firewalled open,
  # but every request (other than /health) requires the bearer/x-api-key
  # value in apiKeyFile.
  services.ninfer = {
    enable = true;
    artifactPath = "/var/lib/ninfer/models/qwen3.8-27b-nvfp4-vision-dflash2.ninfer";
    host = "0.0.0.0";
    port = 8080;
    apiKeyFile = "/var/lib/ninfer/api-key.txt";
    openFirewall = true;
    extraFlags = [
      "--max-context"
      "262144"
      "--kv-capacity"
      "auto"
      "--max-concurrency"
      "3"
      "--kv-dtype"
      "int8"
      "--spec"
      "dflash2"
      "--draft-tokens"
      "7"
      "--vision"
      "--preserve-thinking"
    ];
  };

  # zram as fast primary swap; a declaratively-sized swapfile on the
  # ext4 root (see hardware-configuration.nix's swapDevices) acts as an
  # additional OOM safety net / future hibernation headroom.
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
