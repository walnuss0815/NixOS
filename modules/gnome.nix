{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    gnome3.gnome-tweaks
    gnome3.dconf-editor
    gnomeExtensions.dash-to-dock
    gnomeExtensions.appindicator
    gnomeExtensions.clipboard-indicator
    gnomeExtensions.system-monitor
    arc-icon-theme

    # Config
    xbindkeys # xbindkeys-config
    xdotool
  ];

  environment.gnome.excludePackages = (with pkgs; [
    gnome-tour
  ]) ++ (with pkgs.gnome; [
    gnome-music
    epiphany # web browser
    totem # video player
    tali # poker game
    iagno # go game
    hitori # sudoku game
    atomix # puzzle game
  ]);

  services.xserver = {
    displayManager.gdm = {
      wayland = false;
      enable = true;
    };
    desktopManager = {
      gnome.enable = true;
    };
  };

}
