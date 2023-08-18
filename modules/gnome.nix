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

  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;

    displayManager.gdm = {
      wayland = false;
      enable = true;
    };
    desktopManager = {
      gnome.enable = true;
    };
  };

}
