# System-level Hyprland module
#
# Enables the Hyprland Wayland compositor and the SilentSDDM display manager.
# `programs.hyprland.enable` also takes care of a few things for us:
#   - installs the hyprland package and adds its session to the display manager
#   - enables the XDG desktop portal framework and registers the Hyprland
#     portal (screensharing) -- see xdg.portal below
#   - sets up a setuid wrapper so Hyprland can raise its own scheduling priority
{ pkgs, ... }: {
  # Enable the Hyprland Wayland compositor
  programs.hyprland.enable = true;

  # -----------------------------------------------------------------------
  # Display manager
  # -----------------------------------------------------------------------
  programs.silentSDDM = {
    enable = true;
    theme = "default";
  };

  # -----------------------------------------------------------------------
  # X11 compatibility layer (required by SDDM and some XWayland apps)
  # -----------------------------------------------------------------------
  services.xserver = {
    enable = true;
    excludePackages = with pkgs; [
      xterm # Not needed, kitty is the terminal
    ];
  };

  # -----------------------------------------------------------------------
  # XDG Desktop Portal: required for screensharing and file-open dialogs
  # under Wayland.
  #
  # `programs.hyprland` already enables the portal framework and registers
  # xdg-desktop-portal-hyprland, so we only add the GTK portal here -- the
  # Hyprland portal does not implement a file chooser.
  # -----------------------------------------------------------------------
  xdg.portal = {
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  # -----------------------------------------------------------------------
  # Storage & filesystem services
  # -----------------------------------------------------------------------
  services.udisks2.enable = true; # Auto-mounting USB drives (udiskie)
  services.gvfs.enable = true; # Trash, network mounts, etc.

  # udev rules for GNOME settings daemon (needed for media keys, power
  # profiles, etc.)
  services.udev.packages = with pkgs; [ gnome-settings-daemon ];
}
