# Self-hosted GitHub Actions runner for the RocketPadPlatforms org, running
# on a Proxmox VM (see hosts/rpp-github-runner*/README.md for the VM setup
# and install runbook).
#
# Goal: behave like GitHub's ubuntu-latest runner as far as the workflows
# are concerned, because those workflows (and the third-party actions they
# use) were written against it:
#   - rootful Docker that the job user can reach (kind needs privileged
#     containers, which rootless Docker cannot provide)
#   - passwordless sudo (setup actions run `sudo install ... /usr/local/bin`)
#   - a job-writable /usr/local/bin on PATH (e.g. `curl -o /usr/local/bin/yq`)
#   - /bin/bash and other FHS paths (envfs) and a dynamic loader for
#     downloaded binaries (nix-ld, imported via modules/system/nix-ld)
#
# A VM is used instead of an LXC container on purpose: inside an
# unprivileged container the kubelet of kind's nodes runs in a user
# namespace and refuses to start on Kubernetes < 1.37 without the
# KubeletInUserNamespace feature gate (no /dev/kmsg). In a VM it behaves
# exactly like on GitHub-hosted runners.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  runnerName = "rpp";
  runnerUser = "github-runner";
  # systemd unit created by services.github-runners.<runnerName>
  runnerService = "github-runner-${runnerName}";
  # Job workspace. The module's default is the RuntimeDirectory under /run,
  # a size-limited tmpfs, which is too small for checkouts and vendored
  # charts. The module empties this directory on every service start.
  workDir = "/var/lib/github-runner-work";
  # HOME of the runner and its jobs. Kept apart from workDir on purpose:
  # the module also puts the runner's credential links and _diag into
  # workDir, which must survive between jobs, while HOME must not.
  # Actions write credentials to HOME (e.g. `git config --global
  # url.<token>.insteadOf` in vendir-check, `docker login`, kubeconfigs)
  # and never remove them. With a HOME that persists, an expired token of
  # an earlier job is found first by later jobs and fails them.
  homeDir = "/var/lib/github-runner-home";
  # Empties HOME before and after every job, so each job starts clean like
  # on GitHub-hosted runners. The runner picks the interpreter of a hook by
  # its file extension, hence the .sh. The path is fixed instead of $HOME
  # so that a wrong environment can never empty another directory. sudo
  # removes files that jobs created as root.
  jobHook = pkgs.writeShellScript "github-runner-job-hook.sh" ''
    set -euo pipefail
    /run/wrappers/bin/sudo -n ${pkgs.findutils}/bin/find ${homeDir} -mindepth 1 -delete
  '';
in
{
  # --- Runner -------------------------------------------------------------

  services.github-runners.${runnerName} = {
    enable = true;
    url = "https://github.com/RocketPadPlatforms";
    name = config.networking.hostName;
    # Take over a stale registration with the same name, e.g. after a
    # reinstall of the VM.
    replace = true;
    user = runnerUser;
    group = runnerUser;
    inherit workDir;
    # Placed manually, never in the Nix store. A registration token (valid
    # for one hour) is enough: it is only used when the runner registers,
    # which happens on the first start and again only when the token file's
    # content or one of the registration settings above changes. See the
    # host README for how to create and place it.
    tokenFile = "/var/lib/secrets/github-runner.token";
    # Not part of the registration settings, so changing these does not
    # require a new registration token.
    extraEnvironment = {
      HOME = homeDir;
      ACTIONS_RUNNER_HOOK_JOB_STARTED = "${jobHook}";
      ACTIONS_RUNNER_HOOK_JOB_COMPLETED = "${jobHook}";
    };
    extraPackages = with pkgs; [
      bashInteractive
      curl
      diffutils
      docker
      docker-buildx
      file
      findutils
      gawk
      getent
      gnugrep
      gnumake
      gnused
      gnutar
      gzip
      hostname
      iproute2
      jq
      kubectl
      openssh
      openssl
      procps
      python3
      unzip
      util-linux
      wget
      which
      xz
      zip
      zstd
    ];
    # The module sandboxes the service heavily. Jobs here need root via
    # sudo (setuid), Docker, mounts and arbitrary namespaces, so turn the
    # sandbox off. Isolation comes from the VM itself, like on
    # GitHub-hosted runners.
    serviceOverrides = {
      AmbientCapabilities = lib.mkForce [ ];
      CapabilityBoundingSet = lib.mkForce [ ];
      DeviceAllow = lib.mkForce [ ];
      SystemCallFilter = lib.mkForce [ ];
      RestrictAddressFamilies = lib.mkForce [ ];
      NoNewPrivileges = false;
      PrivateDevices = false;
      PrivateMounts = false;
      PrivateTmp = false;
      PrivateUsers = false;
      ProtectClock = false;
      ProtectControlGroups = false;
      ProtectHome = false;
      ProtectHostname = false;
      ProtectKernelLogs = false;
      ProtectKernelModules = false;
      ProtectKernelTunables = false;
      ProtectSystem = false;
      ProtectProc = "default";
      RestrictNamespaces = false;
      RestrictRealtime = false;
      RestrictSUIDSGID = false;
      UMask = "0022";
      # Without ephemeral the module sets Restart=no, so a crashed runner
      # would stay offline until the next reboot.
      Restart = lib.mkForce "always";
      RestartSec = "10s";
    };
  };

  systemd.services.${runnerService} = {
    # PATH order: the job-writable /usr/local/bin first (tools installed by
    # setup actions win, as on ubuntu-latest), then the setuid wrappers so
    # `sudo` resolves to the real one, then the module's packages, then the
    # system profile as a fallback.
    path = lib.mkMerge [
      (lib.mkBefore [
        "/usr/local"
        "/run/wrappers"
      ])
      (lib.mkAfter [ "/run/current-system/sw" ])
    ];
    # Never restart the runner during `nixos-rebuild switch` (autoUpgrade
    # below), as that would kill a running job. Changes take effect on the
    # next reboot or a manual `systemctl restart github-runner-rpp`.
    restartIfChanged = false;
    after = [ "docker.service" ];
    wants = [ "docker.service" ];
  };

  # The runner module would set HOME to workDir; extraEnvironment above
  # points it to homeDir instead.
  users.users.${runnerUser} = {
    isSystemUser = true;
    group = runnerUser;
    extraGroups = [ "docker" ];
  };
  users.groups.${runnerUser} = { };

  security.sudo.extraRules = [
    {
      users = [ runnerUser ];
      commands = [
        {
          command = "ALL";
          options = [
            "NOPASSWD"
            "SETENV"
          ];
        }
      ];
    }
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/secrets 0700 root root -"
    "d ${workDir} 0750 ${runnerUser} ${runnerUser} -"
    "d ${homeDir} 0750 ${runnerUser} ${runnerUser} -"
    # Writable for jobs, like on GitHub-hosted runners.
    "d /usr/local 0755 root root -"
    "d /usr/local/bin 0755 ${runnerUser} ${runnerUser} -"
  ];

  # /bin/bash, /usr/bin/python3, ... for scripts with FHS shebangs.
  services.envfs.enable = true;

  # --- Docker -------------------------------------------------------------

  # Rootful on purpose (unlike modules/system/docker): kind runs its nodes
  # as privileged containers.
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      log-driver = "local";
    };
    # kind node images are about 1 GB per Kubernetes version.
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
  };
  # Same reason as for the runner: a restart during autoUpgrade would kill
  # the kind cluster of a running job.
  systemd.services.docker.restartIfChanged = false;

  # --- Kernel and network for kind ----------------------------------------

  boot.kernelModules = [
    "overlay"
    "br_netfilter"
  ];
  boot.kernel.sysctl = {
    # Each kind node runs its own systemd and kubelet, which use many
    # inotify instances (kind known issue "too many open files").
    "fs.inotify.max_user_instances" = 8192;
    "fs.inotify.max_user_watches" = 1048576;
  };

  networking.firewall = {
    # Traffic between kind nodes and pods goes over Docker bridges.
    trustedInterfaces = [
      "docker0"
      "br-+"
    ];
    # Pod traffic leaves through different interfaces than it arrives on.
    checkReversePath = "loose";
  };

  # --- VM basics ----------------------------------------------------------

  services.qemuGuest.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Source: https://github.com/walnuss0815.keys
  users.users.alexander.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP9agMLuqQcDPEzPnTTT48UYrsqgyvW3VtfG8JQW3wr2"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILiJPICLeqhAWEuoM9d+IUvM7uDk4kLmgQwowRuybKDn"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL6NGjI8HfBHh4k113IXMOLraYjHTMdNJyu9+7lIbcty"
  ];
  # alexander has no password on these hosts (SSH keys only), so sudo
  # cannot ask for one. Also lets `nixos-rebuild --target-host` copy
  # closures as alexander.
  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [ "@wheel" ];

  # --- Updates ------------------------------------------------------------

  # Pulls this flake from GitHub nightly (the hostname selects the
  # configuration). The runner and Docker are not restarted by the switch
  # (see restartIfChanged above); a reboot inside the window applies new
  # kernels, and with them new runner versions. The runner is registered
  # with --disableupdate, so this is also what keeps it recent enough for
  # GitHub to keep sending it jobs.
  system.autoUpgrade = {
    enable = true;
    flake = "github:walnuss0815/NixOS/wip";
    dates = "03:00";
    randomizedDelaySec = "45min";
    allowReboot = true;
    rebootWindow = {
      lower = "03:00";
      upper = "05:00";
    };
  };
}
