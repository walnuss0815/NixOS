{ config, pkgs, ... }: {
  services.netbird = {
    useRoutingFeatures = "client";
    clients = {
      personal = {
        name = "personal";
        port = 51820;
        autoStart = false;
        ui.enable = true;
      };
    };
  };
}
