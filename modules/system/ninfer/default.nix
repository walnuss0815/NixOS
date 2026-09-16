# NInfer HTTP server: local, OpenAI-/Anthropic-compatible API for a single
# resident model on one NVIDIA GPU. See hosts/owhug-pc1/NINFER-SETUP.md for
# the (manual, GPU-bound) steps to build the model artifact this points at -
# that conversion can't be expressed as a Nix derivation since it downloads
# ~80GB of upstream checkpoints and runs upstream's own conversion tooling.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.ninfer;
in
{
  options.services.ninfer = {
    enable = lib.mkEnableOption "NInfer local LLM HTTP server";

    # Not in nixpkgs (see ../../../pkgs/ninfer); called directly rather than
    # via an overlay, matching this repo's convention for other out-of-tree
    # packages (see modules/user/ai/mcp.nix, opencode.nix).
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../pkgs/ninfer { };
      description = "The ninfer package to use.";
    };

    artifactPath = lib.mkOption {
      type = lib.types.path;
      example = "/var/lib/ninfer/models/qwen3.8-27b-nvfp4-vision-dflash2.ninfer";
      description = ''
        Path to the v3 `.ninfer` model artifact to load. This file is not
        built by Nix - see hosts/owhug-pc1/NINFER-SETUP.md.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      example = "0.0.0.0";
      description = "IP address ninfer-serve listens on.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port ninfer-serve listens on.";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/var/lib/ninfer/api-key.txt";
      description = ''
        Path to a file whose contents are required as the OpenAI bearer
        token / Anthropic `x-api-key` header value. Read at service start
        via `--api-key "$(cat ...)"` so the secret itself never appears in
        the unit file or the Nix store - only this path reference does.
        Generate it out of band, e.g. `openssl rand -base64 32 > <path>`.
      '';
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "--max-context"
        "262144"
        "--kv-capacity"
        "auto"
        "--max-concurrency"
        "3"
        "--kv-dtype"
        "int8"
        "--spec"
        "dflash2"
        "--draft-tokens"
        "7"
        "--vision"
        "--preserve-thinking"
      ];
      description = "Extra literal ninfer-serve CLI flags, appended as-is.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open `port` in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.ninfer = {
      description = "NInfer local LLM HTTP server";
      wants = [ "network.target" ];
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      # A shell script rather than a static ExecStart argv: the API key has
      # to be read from apiKeyFile at process start, not interpolated into
      # the unit at build time.
      script = ''
        set -euo pipefail
        args=(
          --host ${lib.escapeShellArg cfg.host}
          --port ${toString cfg.port}
        )
        ${lib.optionalString (cfg.apiKeyFile != null) ''
          args+=(--api-key "$(cat ${lib.escapeShellArg cfg.apiKeyFile})")
        ''}
        args+=(${lib.concatMapStringsSep " " lib.escapeShellArg cfg.extraFlags})
        exec ${lib.getExe' cfg.package "ninfer-serve"} ${lib.escapeShellArg cfg.artifactPath} "''${args[@]}"
      '';

      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 10;

        DynamicUser = true;
        StateDirectory = "ninfer";
        CacheDirectory = "ninfer";
        WorkingDirectory = "/var/lib/ninfer";

        # GPU access. Mirrors services.llama-cpp's approach in nixpkgs;
        # unverified whether DynamicUser also needs explicit membership in
        # "video"/"render" for /dev/nvidia* access on this host - check on
        # first deploy and add SupplementaryGroups here if the service
        # fails to see the GPU.
        PrivateDevices = false;

        AmbientCapabilities = [ "" ];
        CapabilityBoundingSet = [ "" ];
        LockPersonality = true;
        MemoryDenyWriteExecute = false; # JIT/codegen paths in CUDA runtime libs
        NoNewPrivileges = true;
        PrivateMounts = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
