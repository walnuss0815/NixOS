{
  pkgs,
  gnome,
  ...
}:
{
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

  environment.systemPackages = (with pkgs; [ gnomeExtensions.appindicator ]) ++ [ gnome.adwaita-icon-theme ];

  programs.dconf.enable = true;

  services.udev.packages = with pkgs; [ gnome.gnome-settings-daemon ];
  services.dbus.packages = with pkgs; [ gnome2.GConf ];
}
