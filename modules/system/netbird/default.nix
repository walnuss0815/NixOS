{ config, pkgs, ... }: {
  services.netbird = {
    useRoutingFeatures = "client";
    clients = {
      personal = {
        name = "personal";
        port = 51820;
        autoStart = false;
        ui.enable = true;
        # # Need to fix the issue:
        # # Exactly one of users.users.alexander.isSystemUser and users.users.alexander.isNormalUser must be set.
        # user = {
        #   name = "alexander";
        # };
      };
    };
  };
}
