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

  # Open app on its special workspace the first time, then toggle it.
  dynamicSpecialWorkspace = pkgs.writeShellScript "special-workspace" ''
    APP=$1
    APP_CLASS=$2
    WORKSPACE=$3

    # Check if client exists using hyprctl
    if ${pkgs.hyprland}/bin/hyprctl clients -j | ${pkgs.jq}/bin/jq -e --arg class "$APP_CLASS" '.[] | select(.class == $class)' > /dev/null; then
      ${pkgs.hyprland}/bin/hyprctl dispatch togglespecialworkspace "$WORKSPACE"
    else
      ${pkgs.hyprland}/bin/hyprctl dispatch exec "[workspace special:$WORKSPACE] $APP"
    fi
  '';

  # Dynamically detect the internal laptop display and disable/enable it when
  # the lid is closed/opened -- useful when docked to an external monitor.
  lidSwitchHandler = pkgs.writeShellScript "lid-switch-handler" ''
    monitor=$(${pkgs.hyprland}/bin/hyprctl monitors all -j |
      ${pkgs.jq}/bin/jq -r '.[] | select(.name | test("eDP|LVDS|DSI|unknown")) | .name' |
      head -1)
    [ -n "$monitor" ] || exit 0
    if grep -q "closed" /proc/acpi/button/lid/*/state 2>/dev/null; then
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "$monitor, disable"
    else
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "$monitor, preferred, auto, 1"
    fi
  '';
in
{
  # ---------------------------------------------------------------------------
  # Core Hyprland ecosystem packages
  # ---------------------------------------------------------------------------
  home.packages = with pkgs; [
    # Tiling compositor and utilities
    kitty
    hyprshutdown
    jq

    # Essential GUI applications (GNOME circle, dark-theme friendly)
    gnome-calculator
    evince
    loupe
    gnome-text-editor
    file-roller

    # File manager, networking, bluetooth, audio
    nautilus
    ffmpegthumbnailer
    pavucontrol
    pasystray
    pamixer
    brightnessctl
    wl-clipboard
    playerctl
    grim
    slurp
    wdisplays

    # Theming: fonts, icons, cursors
    nerd-fonts.symbols-only
    papirus-icon-theme
  ];

  fonts.fontconfig.enable = true;

  xdg.desktopEntries = {
    shutdown = {
      name = "Shutdown";
      icon = "system-shutdown";
      exec = "hyprshutdown --top-label \"Shutting down...\" --post-cmd \"systemctl poweroff\"";
      categories = [ "System" "Utility" ];
      terminal = false;
    };
    reboot = {
      name = "Reboot";
      icon = "system-reboot";
      exec = "hyprshutdown --top-label \"Restarting...\" --post-cmd \"systemctl reboot\"";
      categories = [ "System" "Utility" ];
      terminal = false;
    };
    suspend = {
      name = "Suspend";
      icon = "system-suspend";
      exec = "systemctl suspend";
      categories = [ "System" "Utility" ];
      terminal = false;
    };
    lock = {
      name = "Lock";
      icon = "system-lock-screen";
      exec = "loginctl lock-session";
      categories = [ "System" "Utility" ];
      terminal = false;
    };
  };

  # ---------------------------------------------------------------------------
  # Dark mode across all toolkits (GNOME DCONF)
  # ---------------------------------------------------------------------------
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        gtk-theme = "Adwaita-dark";
        color-scheme = "prefer-dark";
        font-name = "Noto Sans Medium 11";
        document-font-name = "Noto Sans Medium 11";
        monospace-font-name = "Noto Sans Mono Medium 11";
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

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;
    configType = "hyprlang";
    settings = {
      exec-once = [
        "waybar"
        "mako"
        "udiskie -t"
        "syshud"
        "${lidSwitchHandler}"
      ];

      env = [
        "XCURSOR_THEME,WhiteSur-cursors"
        "XCURSOR_SIZE,24"
        "GTK_THEME,Adwaita-dark"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
        "GDK_SCALE,1"
        "GDK_DPI_SCALE,1.0"
      ];

      monitor = [
        "eDP-1, 1920x1080, 0x1440, 1" # Built-in screen
        "DP-7,  2560x1440, 0x0,    1" # Left screen
        "DP-4,  2560x1440, 2560x0, 1" # Right screen
        ",      preferred, auto,   auto"
      ];

      input = {
        kb_layout = "de";
        numlock_by_default = true;
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
        };
      };
      general = {
        gaps_in = 0;
        gaps_out = 0;
        border_size = 2;
        "col.active_border" = "rgba(33ccffee)";
        "col.inactive_border" = "rgba(595959aa)";
        layout = "dwindle";
      };
      decoration.rounding = 0;
      animations = {
        enabled = true;
        bezier = [ "myBezier, 0.05, 0.9, 0.1, 1.05" ];
        animation = [
          "windows, 1, 7, myBezier"
          "border, 1, 10, default"
          "fade, 1, 7, default"
          "workspaces, 1, 6, default"
        ];
      };
      dwindle.preserve_split = true;

      "$mainMod" = "SUPER";
      bind = [
        # Applications
        "$mainMod, RETURN, exec, kitty"
        "$mainMod, Q, killactive,"
        "$mainMod, M, exit,"
        "$mainMod, F, fullscreen,"
        "$mainMod, SPACE, exec, fuzzel"
        "$mainMod, R, exec, fuzzel"
        "$mainMod, B, exec, firefox"
        "$mainMod, E, exec, nautilus --new-window"

        # Workspaces
        "$mainMod, S, exec, ${dynamicSpecialWorkspace} spotify Spotify spotify"
        "$mainMod, W, exec, hyprctl dispatch renameworkspace $(hyprctl activeworkspace -j | jq '.id') \"$(fuzzel -d -p 'Rename workspace: ')\""

        # Screenshots
        ", PRINT, exec, hyprshot -m region -o ~/Pictures/Screenshots"
        "SHIFT, PRINT, exec, hyprshot -m output -o ~/Pictures/Screenshots"
        # Window focus (arrow keys)
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"

        # Window movement
        "$mainMod SHIFT, left, movewindow, l"
        "$mainMod SHIFT, right, movewindow, r"
        "$mainMod SHIFT, up, movewindow, u"
        "$mainMod SHIFT, down, movewindow, d"

        # Workspaces 1-5
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"

        "$mainMod SHIFT, 1, movetoworkspace, 1"
        "$mainMod SHIFT, 2, movetoworkspace, 2"
        "$mainMod SHIFT, 3, movetoworkspace, 3"
        "$mainMod SHIFT, 4, movetoworkspace, 4"
        "$mainMod SHIFT, 5, movetoworkspace, 5"

        "$mainMod ALT, right, workspace, m+1"
        "$mainMod ALT, left, workspace, m-1"

        # Media keys
        ", XF86AudioRaiseVolume, exec, pamixer -i 5"
        ", XF86AudioLowerVolume, exec, pamixer -d 5"
        ", XF86AudioMute, exec, pamixer -t"
        ", XF86AudioMicMute, exec, pamixer --default-source -t"
        ", Pause, exec, playerctl play-pause"

        # Brightness
        ", XF86MonBrightnessUp, exec, brightnessctl s +5%"
        ", XF86MonBrightnessDown, exec, brightnessctl s 5%-"

        # Hardware function keys
        ", XF86Display, exec, wdisplays"
        ", XF86WLAN, exec, nmcli radio wifi"
        ", XF86Bluetooth, exec, bluetoothctl power toggle"
        ", XF86Favorites, exec, hyprshot -m region -o ~/Pictures/Screenshots"

        # Keyboard backlight (ThinkPad -- single key cycles brightness)
        ", XF86KbdBrightnessUp, exec, ${kbdBacklightToggle}"
        ", XF86KbdBrightnessDown, exec, ${kbdBacklightToggle}"

        # Lock screen
        "$mainMod, L, exec, hyprlock"

        # Clipboard history
        "$mainMod, V, exec, cliphist list | fuzzel --dmenu --prompt 'Clipboard' | cliphist decode | wl-copy"
      ];
      bindl = [
        # Media keys
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"

        # Lid-switch handler (dynamically detects internal display)
        ", switch:on:Lid Switch, exec, ${lidSwitchHandler}"
        ", switch:off:Lid Switch, exec, ${lidSwitchHandler}"
      ];
      windowrule = [ "match:class .*, suppress_event maximize fullscreen" ];
    };
  };

  services.hyprpolkitagent = {
    enable = true;
  };

  programs.hyprshot = {
    enable = true;
  };

  services.cliphist = {
    enable = true;
  };

  services.blueman-applet = {
    enable = true;
  };

  services.network-manager-applet = {
    enable = true;
  };

  services.udiskie = {
    enable = true;
  };

  services.pasystray = {
    enable = true;
  };

  services.swayosd = {
    enable = true;
  };

  services.hyprpaper = {
    enable = true;
    settings = {
      splash = false;
      wallpaper = [ " ,${config.home.homeDirectory}/Pictures/Wallpapers/, cover" ];
    };
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      background = [{ monitor = ""; path = "${config.home.homeDirectory}/Pictures/Wallpapers/"; blur_passes = 3; blur_size = 10; noise = 0.05; }];
      "input-field" = [{
        monitor = "";
        size = "240, 54";
        outline_thickness = 3;
        dots_size = 0.2;
        dots_spacing = 0.2;
        dots_center = true;
        outer_color = "rgba(0, 0, 0, 0)";
        inner_color = "rgba(255, 255, 255, 0.08)";
        font_color = "rgba(255, 255, 255, 0.9)";
        fade_on_empty = false;
        rounding = 14;
        placeholder_text = "";
        fail_color = "rgba(255, 100, 100, 1.0)";
        fail_text = "";
      }];
      label = [
        {
          monitor = "";
          text = "cmd[update:1000] echo \"$(date '+%H:%M')\"";
          color = "rgba(255, 255, 255, 0.9)";
          font_size = 72;
          font_family = "Noto Sans";
          position = "0, -70";
          halign = "center";
          valign = "center";
          shadow_passes = 2;
          shadow_size = 3;
          shadow_color = "rgba(0, 0, 0, 0.5)";
        }
        {
          monitor = "";
          text = "cmd[update:1000] echo \"$(date '+%A, %B %d')\"";
          color = "rgba(255, 255, 255, 0.6)";
          font_size = 20;
          font_family = "Noto Sans";
          position = "0, -120";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
      };
      listener = [
        { timeout = 150; on-timeout = "brightnessctl -s set 10"; on-resume = "brightnessctl -r"; }
        { timeout = 150; on-timeout = "brightnessctl -sd rgb:kbd_backlight set 0"; on-resume = "brightnessctl -rd rgb:kbd_backlight"; }
        { timeout = 300; on-timeout = "loginctl lock-session"; }
        { timeout = 330; on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'"; on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })' && brightnessctl -r"; }
        { timeout = 1800; on-timeout = "systemctl suspend"; }
      ];
    };
  };

  programs.waybar = {
    enable = true;
    settings = [{
      layer = "top";
      position = "top";
      height = 30;
      spacing = 4;
      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "clock" ];
      modules-right = [ "battery" "tray" ];
      "hyprland/workspaces" = { disable-scroll = true; all-outputs = false; format = "{name}"; };
      clock = { format = "{:%a %d.%m.%Y  %H:%M}"; tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>"; };
      battery = { states = { warning = 30; critical = 15; }; format = "{capacity}% {icon}"; format-icons = [ "" "" "" "" "" ]; format-charging = "{capacity}%  "; format-plugged = "{capacity}%  "; };
      tray = { spacing = 10; icon-size = 18; };
    }];
    style = ''
      * { border: none; border-radius: 0; font-family: "Noto Sans", "Symbols Nerd Font", sans-serif; font-size: 13px; min-height: 0; }
      window#waybar { background: rgba(30, 30, 30, 0.9); color: #ffffff; border-bottom: 1px solid rgba(255, 255, 255, 0.1); }
      #workspaces button { padding: 0 5px; background: transparent; color: #ffffff; }
      #workspaces button.active { background: rgba(255, 255, 255, 0.15); border-radius: 4px; }
      #workspaces button:hover { background: rgba(255, 255, 255, 0.1); border-radius: 4px; }
      #clock, #battery, #tray { padding: 0 10px; margin: 0 2px; }
      #battery.warning { color: #f9e2af; }
      #battery.critical { color: #f38ba8; }
    '';
  };

  programs.fuzzel = {
    enable = true;
    settings = {
      main = { font = "Noto Sans:size=12"; icons-enabled = true; icon-theme = "Papirus-Dark"; prompt = "Apps>"; layer = "overlay"; width = 56; lines = 8; horizontal-pad = 14; vertical-pad = 10; inner-pad = 8; line-height = 28; };
      colors = { background = "1e1e2eff"; text = "cdd6f4ff"; prompt = "6c7086ff"; input = "cdd6f4ff"; placeholder = "6c7086ff"; selection = "45475aff"; selection-text = "cdd6f4ff"; match = "89b4faff"; border = "45475aff"; };
      border = { width = 0; radius = 16; };
    };
  };

  services.mako = {
    enable = true;
    settings = {
      font = "Noto Sans 12";
      margin = 10;
      width = 320;
      height = 120;
      default-timeout = 6000;
      max-visible = 5;
      corner-radius = 10;
      background-color = "#1e1e1e";
      text-color = "#ffffff";
      border-color = "#89b4fa";
      progress-color = "over #89b4fa";
      "urgency=low" = { default-timeout = 4000; };
      "urgency=normal" = { default-timeout = 6000; };
      "urgency=critical" = { default-timeout = 0; border-color = "#f38ba8"; text-color = "#f38ba8"; };
    };
  };

  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.whitesur-cursors;
    name = "WhiteSur-cursors";
    size = 16;
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
