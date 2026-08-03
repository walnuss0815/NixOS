{ pkgs, config, ... }: {
  services = {
    # Enable the GNOME Desktop Environment.
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;

    xserver = {
      # Enable the X11 windowing system.
      enable = true;
      excludePackages = with pkgs; [
        xterm
      ];
    };
  };

  environment.gnome.excludePackages = with pkgs; [
    epiphany # Browser
    gnome-tour # Tour
  ];

  environment.systemPackages = with pkgs; [
    gnome-network-displays
  ];

  xdg.portal.enable = true;
  xdg.portal.extraPortals = [
    pkgs.xdg-desktop-portal-gnome
  ];

  # Firewall ports for Miracast/Wi-Fi Direct
  networking.firewall.trustedInterfaces = [ "p2p-wl+" ];
  networking.firewall.allowedTCPPorts = [ 7236 7250 ];
  networking.firewall.allowedUDPPorts = [ 7236 5353 ];

  services.udev.packages = with pkgs; [ gnome-settings-daemon ];

  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;
}
