# Settings shared by every host, including the headless adsb-pi1: locale,
# time zone, console keymap, nix features and the base user account. Hosts
# add their own groups and options on top (list options merge).
{ ... }:

{
  time.timeZone = "Europe/Berlin";

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

  console.keyMap = "de";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  users.users.alexander = {
    isNormalUser = true;
    description = "Alexander Weidemann";
    extraGroups = [ "wheel" ];
  };
}
