{ pkgs, config, ... }: {
  home.packages = with pkgs; [
    gnomeExtensions.appindicator
    gnomeExtensions.tailscale-qs
    gnomeExtensions.forge
    papirus-icon-theme
    whitesur-cursors
  ];

  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        enable-hot-corners = false;
        cursor-theme = "WhiteSur-cursors";
        icon-theme = "Papirus-Dark";
      };
      "org/gnome/desktop/wm/preferences" = {
        button-layout = "appmenu:minimize,close";
      };
      "org/gnome/desktop/peripherals/touchpad" = {
        tap-to-click = true;
        two-finger-scrolling-enabled = true;
      };
      "org/gnome/desktop/wm/keybindings" = {
        switch-windows = [ "<Alt>Tab" ];
        switch-windows-backward = [ "<Shift><Alt>Tab" ];
      };
      "org/gnome/shell/window-switcher" = {
        current-workspace-only = false;
      };
    };
  };
}
