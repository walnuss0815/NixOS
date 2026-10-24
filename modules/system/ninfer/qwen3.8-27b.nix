# Shared NInfer deployment for the RTX 5090 hosts (owhug-pc1,
# alexander-pc2): an abliterated (uncensored) Qwen3.8-27B NVFP4 artifact.
# See hosts/owhug-pc1/NINFER-SETUP.md for the setup this depends on, why
# this replaced the official artifact, and for generating apiKeyFile's
# contents. The artifact also contains Vision weights, but --vision is
# deliberately omitted below - see the extraFlags comment.
#
# Import together with ./default.nix (the services.ninfer module). Hosts
# only decide whether the server starts at boot (services.ninfer.onDemand,
# default false = start at boot).
#
# "LAN + API key" exposure: bound to all interfaces and firewalled open,
# but every request (other than /health) requires the bearer/x-api-key
# value in apiKeyFile. The artifact and the key file are placed on each
# host manually; neither is managed by Nix.
{
  pkgs,
  ...
}:

{
  services.ninfer = {
    enable = true;
    # Upstream's own measurements use CUDA 13.1 for sm_120a; nixpkgs' default
    # cudaPackages resolves to 12.9, so override explicitly (see
    # hosts/owhug-pc1/NINFER-SETUP.md).
    package = pkgs.callPackage ../../../pkgs/ninfer { cudaPackages = pkgs.cudaPackages_13_1; };
    artifactPath = "/var/lib/ninfer/models/qwen3.8-27b-huihui-abliterated-nvfp4.ninfer";
    host = "0.0.0.0";
    port = 8080;
    apiKeyFile = "/var/lib/ninfer/api-key.txt";
    openFirewall = true;
    # --vision stays disabled for the same reason as the official artifact
    # (see NINFER-SETUP.md's "Why vision is off"): its encoder workspace
    # cost is independent of --max-context and isn't needed for this
    # deployment's use case. This artifact has no DFlash2 companion
    # weights (only the official target model has those), so --spec
    # switched to mtp - the artifact does carry MTP + the optimized
    # proposal head. --max-context was re-tuned for this artifact's
    # ~19.0GiB resident weight size (vs. 21.1GiB before) on owhug-pc1,
    # with a desktop session sharing the GPU; see NINFER-SETUP.md for the
    # measured values. --max-concurrency depends on how much VRAM the host
    # leaves free, so each host appends it in its own configuration.nix
    # (list definitions merge).
    extraFlags = [
      "--max-context"
      "245760"
      "--kv-capacity"
      "auto"
      "--kv-dtype"
      "int8"
      "--spec"
      "mtp"
      "--draft-tokens"
      "5"
      "--lm-head-draft"
      "--preserve-thinking"
      # The 30 s default expires requests queued behind a long one; match
      # LiteLLM's 1800 s per-call timeout instead.
      "--pending-timeout-ms"
      "1800000"
    ];
  };
}
