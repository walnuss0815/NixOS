# Host-specific settings only; locale, user, audio, packages and the rest of
# the shared desktop setup live in modules/system/{common,desktop}.

{ ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-dece85fc-0df8-4bf3-8d75-9dbbcc08c6dc".device =
    "/dev/disk/by-uuid/dece85fc-0df8-4bf3-8d75-9dbbcc08c6dc";
  networking.hostName = "alexander-nb2"; # Define your hostname.

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "alexander";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
