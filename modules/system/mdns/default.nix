{
  # systemd-resolved is the stub resolver; NetworkManager pushes per-link
  # DNS configuration into it. resolvconf is redundant next to it.
  networking.resolvconf.enable = false;
  services.resolved = {
    enable = true;
    settings.Resolve.MulticastDNS = "yes";
  };

  # 2 = "yes": resolve *.local and announce this host's name on every
  # NetworkManager-managed link. NetworkManager's default for the resolved
  # backend is "no", so resolved's global MulticastDNS setting above would
  # otherwise never be applied to any interface.
  networking.networkmanager.settings.connection.mdns = 2;

  # Explicit, so mDNS does not silently depend on avahi's openFirewall
  # default. avahi stays enabled through GNOME (printer/scanner browsing)
  # with publishing off, so there is no second responder on port 5353.
  networking.firewall.allowedUDPPorts = [ 5353 ];
}
