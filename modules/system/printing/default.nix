{ config, pkgs, ... }: {

  services.printing = {
    enable = true;
    browsing = true;
    drivers = with pkgs; [ cups-filters ];
  };

  hardware.printers = {
    ensureDefaultPrinter = "Alexander_Laser_BW";
    ensurePrinters = [
      {
        name = "Alexander_Laser_BW";
        location = "Office";
        deviceUri = "ipp://192.168.10.174/ipp";
        model = "everywhere";
      }
    ];
  };

  # Enable scanner support
  hardware.sane = {
    enable = true;
    extraBackends = [ ];
  };
  environment.systemPackages = [ pkgs.simple-scan ];
}
