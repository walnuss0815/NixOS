{ pkgs, config, ... }: {
  home.packages = with pkgs; [
    gnomeExtensions.appindicator
    gnomeExtensions.tailscale-qs
    gnomeExtensions.forge
    papirus-icon-theme
    whitesur-cursors
    exiftool
  ];

  # Nautilus right-click script to strip EXIF/metadata from images.
  # Usage: select one or more images, right-click -> Scripts -> "Strip EXIF Data"
  home.file.".local/share/nautilus/scripts/Strip EXIF Data" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Removes all metadata (EXIF, GPS, IPTC, XMP) from the selected images.
      # The ICC colour profile is kept so the images do not change appearance.
      set -e
      for file in "$@"; do
        exiftool -overwrite_original -all= --icc_profile:all "$file"
      done
      notify-send "Strip EXIF Data" "Stripped metadata from $# image(s)."
    '';
  };

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
        action-double-click-titlebar = "none";
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
        current-workspace-only = true;
      };
      "org/gnome/mutter" = {
        workspaces-only-on-primary = false;
        auto-maximize = false;
        edge-tiling = false;
      };
      "org/gnome/shell/app-switcher" = {
        current-workspace-only = true;
      };
    };
  };
}
