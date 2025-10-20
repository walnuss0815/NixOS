{ pkgs, config, ... }:

{
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
      daemon.settings = {
        experimental = true;
        features = {
          containerd-snapshotter = true;
        };
      };
    };
  };
}
