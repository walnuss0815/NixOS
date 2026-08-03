{ pkgs, config, ... }:

let
  # Keyboard backlight toggle for ThinkPad devices -- cycles brightness from
  # off (0) up to max, then back to off.  Both brightness up and down keys
  # call the same script so the user only needs to press one key repeatedly.
  kbdBacklightToggle = pkgs.writeShellScript "kbd-backlight-toggle" ''
    device=tpacpi::kbd_backlight
    ${pkgs.brightnessctl}/bin/brightnessctl -d "$device" get >/dev/null 2>&1 || exit 0
    level=$(${pkgs.brightnessctl}/bin/brightnessctl -d "$device" get)
    max=$(${pkgs.brightnessctl}/bin/brightnessctl -d "$device" max)
    if [ "$level" -lt "$max" ]; then
      ${pkgs.brightnessctl}/bin/brightnessctl -d "$device" set +1
    else
      ${pkgs.brightnessctl}/bin/brightnessctl -d "$device" set 0
    fi
  '';

  # Gracefully close all apps, exit Hyprland, then power off the machine.
  # hyprshutdown only logs out (returning to the display manager), so a
  # --post-cmd is required to actually shut the system down.
  # NOTE: hyprshutdown is referenced by its store path here (and in the
  # launcher desktop entry below), so it does NOT need to be in home.packages.
  powerOff = pkgs.writeShellScript "power-off" ''
    ${pkgs.hyprshutdown}/bin/hyprshutdown \
      --top-label 'Shutting down...' \
      --post-cmd 'systemctl poweroff'
  '';

  # Clipboard history picker: list cliphist entries in fuzzel and paste the
  # selection back into the clipboard.  fuzzel --dmenu prints the selected
  # entry on stdout, which feeds the decode/copy pipeline.
  clipboardPicker = pkgs.writeShellScript "clipboard-picker" ''
    selected=$(${pkgs.cliphist}/bin/cliphist list |
      ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt 'Clipboard')
    [ -n "$selected" ] || exit 0
    printf '%s' "$selected" | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy
  '';

  # Dynamically detect the internal laptop display and disable/enable it when
  # the lid is closed/opened -- useful when docked to an external monitor.
  lidSwitchHandler = pkgs.writeShellScript "lid-switch-handler" ''
    monitor=$(${pkgs.hyprland}/bin/hyprctl monitors -j |
      ${pkgs.jq}/bin/jq -r '.[] | select(.description | test("eDP|LVDS|DSI|unknown")) | .name' |
      head -1)
    [ -n "$monitor" ] || exit 0
    case "$1" in
      close) ${pkgs.hyprland}/bin/hyprctl keyword monitor "$monitor, disable" ;;
      open)  ${pkgs.hyprland}/bin/hyprctl keyword monitor "$monitor, preferred, auto, 1" ;;
    esac
  '';
in
{
  # ---------------------------------------------------------------------------
  # Core Hyprland ecosystem packages
  # ---------------------------------------------------------------------------
  home.packages = with pkgs; [
    # Tiling compositor and utilities
    waybar
    fuzzel
    mako
    kitty
    hyprpaper
    hyprlock
    hypridle
    hyprshot
    hyprpolkitagent
    cliphist

    # Essential GUI applications (GNOME circle, dark-theme friendly)
    gnome-calculator
    evince
    loupe
    gnome-text-editor

    # File manager, networking, bluetooth, audio
    nautilus
    ffmpegthumbnailer
    networkmanagerapplet
    blueman
    pavucontrol
    pasystray
    pamixer
    brightnessctl
    wl-clipboard
    udiskie
    playerctl
    grim
    slurp
    wdisplays

    # Theming: fonts, icons, cursors
    noto-fonts
    nerd-fonts.symbols-only
    papirus-icon-theme
    whitesur-cursors
  ];

  fonts.fontconfig.enable = true;

  # Expose hyprshutdown in the launcher -- it ships no .desktop.
  xdg.desktopEntries = {
    hyprshutdown = {
      name = "Shutdown";
      genericName = "Hyprland power menu";
      exec = "${powerOff}";
      categories = [ "System" "Utility" ];
    };
  };

  # ---------------------------------------------------------------------------
  # Dark mode across all toolkits (GNOME DCONF)
  # ---------------------------------------------------------------------------
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };
  };

  # ---------------------------------------------------------------------------
  # User directories
  # ---------------------------------------------------------------------------
  home.file = {
    "Pictures/Screenshots/.keep".text = "";
    "Pictures/Wallpapers".source = ./wallpapers;
  };

  # ---------------------------------------------------------------------------
  # XDG configuration files (dotfiles)
  # ---------------------------------------------------------------------------
  xdg.configFile = {
    # -- Hyprland compositor config (generated inline because it needs nix
    #    paths for the custom scripts and polkit agent) --

    "hypr/hyprland.conf".text = ''
      # Options not listed here (monitor auto-detection, gaps, follow_mouse,
      # rounding, layout, ...) are intentionally left at their Hyprland
      # defaults instead of being spelled out.

      # --- Autostart ---
      exec-once = waybar
      exec-once = mako
      exec-once = hypridle
      exec-once = hyprpaper
      exec-once = udiskie -t
      exec-once = nm-applet --indicator
      exec-once = blueman-applet
      exec-once = ${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent
      exec-once = ${pkgs.pasystray}/bin/pasystray
      exec-once = wl-paste --type text --watch cliphist store
      exec-once = hyprctl setcursor WhiteSur-cursors 24

      # --- Environment ---
      env = XCURSOR_THEME,WhiteSur-cursors
      env = XCURSOR_SIZE,24
      env = GTK_THEME,Adwaita-dark
      env = ELECTRON_OZONE_PLATFORM_HINT,auto

      # --- Monitors ---
      monitor = ,preferred,auto,auto

      # --- Input: keyboard layout, touchpad ---
      input {
          kb_layout = de
          follow_mouse = 1
          touchpad {
              natural_scroll = true
              tap-to-click = true
          }
      }

      # --- Visuals ---
      general {
          gaps_in = 0
          gaps_out = 0
          border_size = 2
          col.active_border = rgba(33ccffee)
          col.inactive_border = rgba(595959aa)
          layout = dwindle
      }

      decoration {
          rounding = 0
      }

      animations {
          enabled = true
          bezier = myBezier, 0.05, 0.9, 0.1, 1.05
          animation = windows, 1, 7, myBezier
          animation = border, 1, 10, default
          animation = fade, 1, 7, default
          animation = workspaces, 1, 6, default
      }

      dwindle {
          preserve_split = true
      }

      # --- Keybinds ---
      $mainMod = SUPER

      # Applications
      bind = $mainMod, RETURN, exec, kitty
      bind = $mainMod, Q, killactive,
      bind = $mainMod, M, exit,
      bind = $mainMod, F, fullscreen,
      bind = $mainMod, SPACE, togglefloating,
      bind = $mainMod, R, exec, fuzzel
      bind = $mainMod, B, exec, firefox
      bind = $mainMod, E, exec, nautilus --new-window

      # Screenshots
      bind = , PRINT, exec, hyprshot -m region -o ~/Pictures/Screenshots
      bind = $mainMod SHIFT, PRINT, exec, hyprshot -m output -o ~/Pictures/Screenshots

      # Window focus (Vim-style HJKL)
      bind = $mainMod, H, movefocus, l
      bind = $mainMod, L, movefocus, r
      bind = $mainMod, K, movefocus, u
      bind = $mainMod, J, movefocus, d

      # Window movement
      bind = $mainMod SHIFT, H, movewindow, l
      bind = $mainMod SHIFT, L, movewindow, r
      bind = $mainMod SHIFT, K, movewindow, u
      bind = $mainMod SHIFT, J, movewindow, d

      # Workspaces 1-5
      bind = $mainMod, 1, workspace, 1
      bind = $mainMod, 2, workspace, 2
      bind = $mainMod, 3, workspace, 3
      bind = $mainMod, 4, workspace, 4
      bind = $mainMod, 5, workspace, 5

      bind = $mainMod SHIFT, 1, movetoworkspace, 1
      bind = $mainMod SHIFT, 2, movetoworkspace, 2
      bind = $mainMod SHIFT, 3, movetoworkspace, 3
      bind = $mainMod SHIFT, 4, movetoworkspace, 4
      bind = $mainMod SHIFT, 5, movetoworkspace, 5

      bind = $mainMod, mouse_down, workspace, e+1
      bind = $mainMod, mouse_up, workspace, e-1

      # Media keys
      bind = , XF86AudioRaiseVolume, exec, pamixer -i 5
      bind = , XF86AudioLowerVolume, exec, pamixer -d 5
      bind = , XF86AudioMute, exec, pamixer -t
      bind = , XF86AudioMicMute, exec, pamixer --default-source -t

      bindl = , XF86AudioPlay, exec, playerctl play-pause
      bindl = , XF86AudioNext, exec, playerctl next
      bindl = , XF86AudioPrev, exec, playerctl previous
      bind = , Pause, exec, playerctl play-pause

      # Brightness
      bind = , XF86MonBrightnessUp, exec, brightnessctl s +5%
      bind = , XF86MonBrightnessDown, exec, brightnessctl s 5%-

      # Hardware function keys
      bind = , XF86Display, exec, wdisplays
      bind = , XF86WLAN, exec, nmcli radio wifi
      bind = , XF86Bluetooth, exec, bluetoothctl power toggle
      bind = , XF86Favorites, exec, hyprshot -m region -o ~/Pictures/Screenshots

      # Keyboard backlight (ThinkPad -- single key cycles brightness)
      bind = , XF86KbdBrightnessUp, exec, ${kbdBacklightToggle}
      bind = , XF86KbdBrightnessDown, exec, ${kbdBacklightToggle}

      # Lock screen
      bind = $mainMod, L, exec, hyprlock

      # Power menu
      bind = $mainMod, X, exec, ${powerOff}

      # Clipboard history
      bind = $mainMod SHIFT, V, exec, ${clipboardPicker}

      # --- Lid-switch handler (dynamically detects internal display) ---
      bindl = , switch:on:Lid Switch, exec, ${lidSwitchHandler} close
      bindl = , switch:off:Lid Switch, exec, ${lidSwitchHandler} open

      # --- Misc ---
      suppressevent = maximize
    '';

    # -- Standalone config files (static, no nix interpolation needed) --

    "hypr/hyprpaper.conf".source = ./hyprpaper.conf;
    "hypr/hyprlock.conf".source = ./hyprlock.conf;
    "hypr/hypridle.conf".source = ./hypridle/hypridle.conf;
    "waybar/config.jsonc".source = ./waybar/config.jsonc;
    "waybar/style.css".source = ./waybar/style.css;
    "fuzzel/fuzzel.ini".source = ./fuzzel/fuzzel.ini;
    "mako/config".source = ./mako/config;
  };

  # ---------------------------------------------------------------------------
  # GTK theming (dark, consistent cursor & icons)
  # ---------------------------------------------------------------------------
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
      name = "WhiteSur-cursors";
      package = pkgs.whitesur-cursors;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
    gtk4 = {
      theme = config.gtk.theme;
      extraConfig = {
        gtk-application-prefer-dark-theme = true;
      };
    };
  };
}
