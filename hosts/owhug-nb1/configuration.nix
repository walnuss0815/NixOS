# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ lib, pkgs, ... }:

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
  # check progress.
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    autoGenerateKeys.enable = true;
    autoEnrollKeys = {
      enable = true;
      includeMicrosoftKeys = true; # keep Windows Boot Manager / OEM option-ROMs working
      autoReboot = false; # we control when the finalizing reboot happens
    };
  };

  # Required for TPM2-bound LUKS auto-unlock (crypttabExtraOpts below).
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices = {
    crypted = {
      device = "/dev/disk/by-uuid/edb6d4fa-a4d6-445c-b07b-825ab49a1adf";
      preLVM = true;
      # Allow the TPM2 chip to auto-unlock this volume once a TPM2 keyslot
      # has been enrolled via `systemd-cryptenroll --tpm2-device=auto`.
      # The original passphrase keyslot remains as a fallback.
      crypttabExtraOpts = [ "tpm2-device=auto" ];
    };
  };

  networking.hostName = "owhug-nb1"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # NetworkManager itself is enabled in modules/system/desktop.
  networking.networkmanager = {
    wifi = {
      powersave = false;
      scanRandMacAddress = false;
    };
    plugins = with pkgs; [
      networkmanager-openvpn
    ];
  };

  # Bluetooth
  hardware.bluetooth.enable = true;

  networking.modemmanager.fccUnlockScripts = [
    {
      id = "1eac:1001";
      path = "${pkgs.modemmanager}/share/ModemManager/fcc-unlock.available.d/1eac:1001";
    }
  ];

  # Time zone, locale and nix features: modules/system/common.
  # Base packages (git, vim, home-manager, ...): modules/system/desktop.
  environment.systemPackages = with pkgs; [
    # eSIM
    pcsclite
    nur.repos.linyinfeng.lpac

    # VM
    qemu

    # Secure Boot key management / troubleshooting (see boot.lanzaboote)
    sbctl
  ];

  # eSIM
  services.pcscd.enable = true;

  # Enable firmware update tool
  services.fwupd.enable = true;

  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/70-stm32-dfu.rules" ''
      # DFU (Internal bootloader for STM32 and AT32 MCUs)
      SUBSYSTEM=="usb", ATTRS{idVendor}=="2e3c", ATTRS{idProduct}=="df11", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", TAG+="uaccess"
    '')
  ];

  # Host-specific groups; the account itself is defined in
  # modules/system/{common,desktop}. Don't forget to set a password with
  # ‘passwd’.
  users.users.alexander.extraGroups = [
    "libvirtd"
    "dialout"
    "netbird-personal"
    "video"
  ];

  # Automatic login is disabled; GDM always prompts (password or
  # fingerprint, see services.fprintd below).
  services.displayManager.autoLogin.enable = false;

  # AMD GPU
  services.xserver.videoDrivers = [ "amdgpu" ];
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Latest Linux kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Fix micro SD card reader
  boot.kernelModules = [ "rtsx_pci_sdmmc" ];

  # Touchscreen
  services.xserver.wacom.enable = true;
  boot.blacklistedKernelModules = [ "raydium_i2c_ts" ];

  # Fingerprint reader: login and unlock with fingerprint (if you add one with `fprintd-enroll`)
  services.fprintd.enable = true;

  # Pin the external DELL S2721DGF (serial F1QXV13) as primary for the
  # GDM login screen when docked in the current DP-7/DP-4 layout.
  # Falls back to GNOME's normal auto-detected layout (laptop screen
  # eDP-1 primary) when undocked or docked differently than this.
  # If the dock/port arrangement changes, this may need an additional
  # <configuration> block for the new connector combo.
  environment.etc."xdg/monitors.xml".text = ''
    <monitors version="2">
      <configuration>
        <layoutmode>logical</layoutmode>
        <logicalmonitor>
          <x>0</x>
          <y>0</y>
          <scale>1</scale>
          <primary>yes</primary>
          <monitor>
            <monitorspec>
              <connector>DP-7</connector>
              <vendor>DEL</vendor>
              <product>DELL S2721DGF</product>
              <serial>F1QXV13</serial>
            </monitorspec>
            <mode>
              <width>2560</width>
              <height>1440</height>
              <rate>59.951</rate>
            </mode>
          </monitor>
        </logicalmonitor>
        <logicalmonitor>
          <x>2560</x>
          <y>0</y>
          <scale>1</scale>
          <monitor>
            <monitorspec>
              <connector>DP-4</connector>
              <vendor>DEL</vendor>
              <product>DELL S2721DGF</product>
              <serial>5Y4HC23</serial>
            </monitorspec>
            <mode>
              <width>2560</width>
              <height>1440</height>
              <rate>59.951</rate>
            </mode>
          </monitor>
        </logicalmonitor>
      </configuration>
    </monitors>
  '';

  # Enable flatpak
  services.flatpak.enable = true;

  virtualisation = {
    libvirtd = {
      enable = true;
      # qemu = {
      #   swtpm.enable = true;
      #   ovmf.enable = true;
      #   ovmf.packages = [ pkgs.OVMFFull.fd ];
      # };
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
