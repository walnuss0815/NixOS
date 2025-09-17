{ config, pkgs, ... }: {
  services.netbird = {
    enable = true;
    ui.enable = true;
    clients = {
      personal = {
        name = "netbird";
        port = 51820;
        autoStart = false;
      };
    };
  };
}
