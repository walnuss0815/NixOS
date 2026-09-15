{ pkgs, lib, config, ... }:
let
  wallpaper = ./wallpaper.jpg;
  wallpaperUri = "file://${config.home.homeDirectory}/Pictures/Wallpapers/wallpaper.jpg";
in
{
  home.packages = with pkgs; [
    gnomeExtensions.appindicator
    gnomeExtensions.forge
    # Disabled until this is fixed
    # https://github.com/boerdereinar/copyous/issues/152
    # gnomeExtensions.copyous
    (pkgs.callPackage ../../../pkgs/gnome-shell-extension-claude-usage { })
    papirus-icon-theme
    whitesur-cursors
    exiftool
  ];

  home.file."Pictures/Wallpapers/wallpaper.jpg".source = wallpaper;

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
        accent-color = "orange";
        clock-show-weekday = true;
        show-battery-percentage = true;
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

      "org/gnome/desktop/background" = {
        picture-uri = wallpaperUri;
        picture-uri-dark = wallpaperUri;
        picture-options = "zoom";
      };
      "org/gnome/desktop/screensaver" = {
        picture-uri = wallpaperUri;
      };

      "org/gnome/shell" = {
        enabled-extensions = [
          "appindicatorsupport@rgcjonas.gmail.com"
          "forge@jmmaranan.com"
          "claude-usage@dvdstelt.github.io"
        ];
        favorite-apps = [
          "org.gnome.Nautilus.desktop"
          "code.desktop"
          "spotify.desktop"
          "org.gnome.Console.desktop"
          "firefox.desktop"
          "org.gnome.Geary.desktop"
          "BambuStudio.desktop"
        ];
      };

      # Only the settings that differ from forge's schema defaults are
      # listed here; the rest of the module (tiling, quick settings, etc.)
      # is left at upstream defaults.
      "org/gnome/shell/extensions/forge" = {
        dnd-center-layout = "swap";
        float-always-on-top-enabled = false;
        focus-border-toggle = false;
        window-gap-hidden-on-single = true;
        window-gap-size = lib.hm.gvariant.mkUint32 1;
        window-gap-size-increment = lib.hm.gvariant.mkUint32 0;
      };
      "org/gnome/shell/extensions/forge/keybindings" = {
        con-split-horizontal = [ "<Super>z" ];
        con-split-layout-toggle = [ "<Super>g" ];
        con-split-vertical = [ "<Super>v" ];
        con-stacked-layout-toggle = [ "<Shift><Super>s" ];
        con-tabbed-layout-toggle = [ "<Shift><Super>t" ];
        con-tabbed-showtab-decoration-toggle = [ "<Control><Alt>y" ];
        focus-border-toggle = [ "<Super>x" ];
        prefs-tiling-toggle = [ "<Super>w" ];
        window-focus-down = [ "<Super>j" ];
        window-focus-left = [ "<Super>h" ];
        window-focus-right = [ "<Super>l" ];
        window-focus-up = [ "<Super>k" ];
        window-gap-size-decrease = [ "<Control><Super>minus" ];
        window-gap-size-increase = [ "<Control><Super>plus" ];
        window-move-down = [ "<Shift><Super>j" ];
        window-move-left = [ "<Shift><Super>h" ];
        window-move-right = [ "<Shift><Super>l" ];
        window-move-up = [ "<Shift><Super>k" ];
        window-resize-bottom-decrease = [ "<Shift><Control><Super>i" ];
        window-resize-bottom-increase = [ "<Control><Super>u" ];
        window-resize-left-decrease = [ "<Shift><Control><Super>o" ];
        window-resize-left-increase = [ "<Control><Super>y" ];
        window-resize-right-decrease = [ "<Shift><Control><Super>y" ];
        window-resize-right-increase = [ "<Control><Super>o" ];
        window-resize-top-decrease = [ "<Shift><Control><Super>u" ];
        window-resize-top-increase = [ "<Control><Super>i" ];
        window-snap-center = [ "<Control><Alt>c" ];
        window-snap-one-third-left = [ "<Control><Alt>d" ];
        window-snap-one-third-right = [ "<Control><Alt>g" ];
        window-snap-two-third-left = [ "<Control><Alt>e" ];
        window-snap-two-third-right = [ "<Control><Alt>t" ];
        window-swap-down = [ "<Control><Super>j" ];
        window-swap-last-active = [ "<Super>Return" ];
        window-swap-left = [ "<Control><Super>h" ];
        window-swap-right = [ "<Control><Super>l" ];
        window-swap-up = [ "<Control><Super>k" ];
        window-toggle-always-float = [ "<Shift><Super>z" ];
        window-toggle-float = [ "<Super>p" ];
        workspace-active-tile-toggle = [ "<Shift><Super>w" ];
      };

      # Only the settings that differ from claude-usage's schema defaults
      # are listed here (panel-gauge, show-icon, show-reset already match
      # upstream defaults).
      "org/gnome/shell/extensions/claude-usage" = {
        panel-window = "max";
        show-percentage = false;
        show-tier = false;
        profiles = builtins.toJSON [
          {
            id = "pmtl7dnxn1";
            label = "Claude";
            configDir = "${config.home.homeDirectory}/.claude";
          }
        ];
        profiles-initialized = true;
      };
    };
  };
}
