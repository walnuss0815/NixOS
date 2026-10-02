{ ... }:

{
  # Rootless Docker only. The rootful daemon (virtualisation.docker.enable)
  # is deliberately off: the user is not in the `docker` group, so it would
  # be unreachable, and the rootless module installs the CLI and points
  # DOCKER_HOST at the per-user socket on its own.
  virtualisation.docker = {
    enable = false;
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
