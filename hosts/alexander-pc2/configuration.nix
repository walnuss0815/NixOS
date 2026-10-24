# alexander-pc2: headless LLM server (AMD CPU, NVIDIA RTX 5090, RTL8125
# NIC, single NVMe drive). No desktop; NInfer starts at boot. The NInfer
# deployment lives in modules/system/ninfer/qwen3.8-27b.nix. See
# ./README.md for the install runbook and the manual NInfer steps (model
# artifact, API key).
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    # Declarative disk layout; generates fileSystems."/",
    # fileSystems."/boot" and boot.initrd.luks.devices.cryptroot.
    ./disko.nix
  ];

  # --- Boot ---------------------------------------------------------------

  # Lanzaboote replaces the systemd-boot module for Secure Boot signing,
  # so it must be force-disabled here.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Secure Boot: keys are generated on first activation and staged on the
  # ESP for firmware auto-enrollment (see ./README.md). The Microsoft keys
  # are included because the GPU's option ROM is signed with Microsoft's
  # UEFI CA; without them the firmware refuses to initialise the card
  # under Secure Boot.
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    autoGenerateKeys.enable = true;
    autoEnrollKeys = {
      enable = true;
      includeMicrosoftKeys = true; # option ROMs (GPU) are Microsoft-signed
      autoReboot = false; # we control when the finalizing reboot happens
    };
  };

  # Required for TPM2-bound LUKS auto-unlock (crypttabExtraOpts, set via
  # ./disko.nix's cryptroot settings). Without an enrolled TPM2 keyslot
  # every boot waits for the passphrase on the local console.
  boot.initrd.systemd.enable = true;
  security.tpm2.enable = true;

  # Latest Linux kernel (needed for current-gen CPU/GPU driver support).
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # --- Hardware -----------------------------------------------------------

  # NVIDIA driver and CUDA are unfree. Other hosts get this from
  # modules/system/desktop, which this headless host doesn't import.
  nixpkgs.config.allowUnfree = true;

  # NVIDIA GPU, compute only. services.xserver.videoDrivers is set to
  # [ "nvidia" ] via the nixos-hardware common-gpu-nvidia-nonprime module
  # in flake.nix, which is what enables the driver; X itself stays off.
  # Current GPU generations require the open kernel module; the "latest"
  # driver branch is used for current-gen support.
  hardware.nvidia = {
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest;
    # Without a display server nothing keeps the GPU initialised between
    # CUDA clients; the persistence daemon avoids re-initialisation on
    # every NInfer (re)start.
    nvidiaPersistenced = true;
    nvidiaSettings = false;
  };
  # Puts the userspace driver (libcuda) under /run/opengl-driver, where
  # CUDA applications such as ninfer-serve look for it.
  hardware.graphics.enable = true;

  systemd.services.nvidia-power-limit = {
    description = "Set NVIDIA GPU power limit";
    wantedBy = [ "multi-user.target" ];
    before = [ "ninfer.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe' config.hardware.nvidia.package.bin "nvidia-smi"} --power-limit=450";
    };
  };

  # Onboard RTL8125D 2.5GbE NIC: DHCP never completes under the in-tree
  # r8169 driver on this chip revision, so use Realtek's out-of-tree
  # r8125 driver instead.
  boot.extraModulePackages = [ config.boot.kernelPackages.r8125 ];
  boot.blacklistedKernelModules = [ "r8169" ];

  # zram as fast primary swap; the swapfile in hardware-configuration.nix
  # is an additional OOM safety net.
  zramSwap.enable = true;

  # Firmware updates (`fwupdmgr update`).
  services.fwupd.enable = true;

  # --- NInfer -------------------------------------------------------------

  # No desktop session on this GPU, so the ~1GiB (+~800MiB fluctuation)
  # that keeps owhug-pc1 at concurrency 1 is free here; two parallel
  # agent sessions instead. If startup fails with "minimum Engine runtime
  # reservation requires N bytes", lower --max-context in
  # modules/system/ninfer/qwen3.8-27b.nix (~33.8KB per token, see
  # hosts/owhug-pc1/NINFER-SETUP.md) or go back to 1.
  services.ninfer.extraFlags = [
    "--max-concurrency"
    "2"
  ];

  # --- Network ------------------------------------------------------------

  networking.hostName = "alexander-pc2";

  # No NetworkManager on this headless host (that comes with
  # modules/system/desktop). DHCP via systemd-networkd on any wired
  # interface; matching en* keeps this independent of the exact name.
  networking.useDHCP = false;
  networking.useNetworkd = true;
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "yes";
  };

  # --- Remote access ------------------------------------------------------

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Source: https://github.com/walnuss0815.keys
  users.users.alexander.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP9agMLuqQcDPEzPnTTT48UYrsqgyvW3VtfG8JQW3wr2"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILiJPICLeqhAWEuoM9d+IUvM7uDk4kLmgQwowRuybKDn"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL6NGjI8HfBHh4k113IXMOLraYjHTMdNJyu9+7lIbcty"
    # owhug-nb1's remote-build key (nix.buildMachines there). Restricted
    # to the Nix daemon protocol: alexander has passwordless sudo here,
    # so an unrestricted key would grant root.
    ''command="${config.nix.package}/bin/nix-daemon --stdio",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAoJda+/GIOAn/P05tS/2pLK6eJf26K/7X43fILrLemf nix-builder@owhug-nb1''
  ];
  # alexander has no password on this host (SSH keys only), so sudo cannot
  # ask for one. Also lets `nixos-rebuild --target-host` copy closures as
  # alexander.
  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [ "@wheel" ];

  environment.systemPackages = with pkgs; [
    git
    vim

    # Secure Boot key management / troubleshooting (see boot.lanzaboote)
    sbctl

    # TPM2 troubleshooting (see ./disko.nix's cryptroot settings)
    tpm2-tools
  ];

  # --- Updates ------------------------------------------------------------

  # Pulls this flake from GitHub nightly (the hostname selects the
  # configuration), like the runner VMs. Reboots inside the window apply
  # new kernels/drivers; this only works unattended once the TPM2 keyslot
  # is enrolled (see ./README.md), otherwise the host waits for the LUKS
  # passphrase after the reboot.
  system.autoUpgrade = {
    enable = true;
    flake = "github:walnuss0815/NixOS/wip";
    dates = "03:00";
    randomizedDelaySec = "45min";
    allowReboot = true;
    rebootWindow = {
      lower = "03:00";
      upper = "05:00";
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.11"; # Did you read the comment?
}
