# Local LLM: llama.cpp serving an abliterated Qwen3.8-27B (Q8_0 GGUF),
# split across both RTX 5090s. One flag set (settingsFor) feeds both ways
# of running it: the "LLM Server" GNOME launcher in the desktop entry and
# the llama-cpp service in the headless "llm" boot entry. The model file
# and API key are placed by hand; see ./LLM-SETUP.md.
{
  lib,
  pkgs,
  ...
}:

let
  # NCCL gives -sm tensor its fast GPU all-reduce; nixpkgs doesn't link it.
  llamaCpp = (pkgs.llama-cpp.override { cudaSupport = true; }).overrideAttrs (old: {
    buildInputs = old.buildInputs ++ [ pkgs.cudaPackages.nccl ];
  });

  # Every session gets the full native context: -c is split per slot.
  settingsFor = parallel: {
    host = "0.0.0.0";
    port = 8080;
    model = "/var/lib/llm/models/Huihui-Qwen3.8-27B-abliterated-Q8_0.gguf";
    alias = "qwen3.8-27b";
    api-key-file = "/var/lib/llm/api-key.txt";
    split-mode = "tensor";
    n-gpu-layers = 999;
    flash-attn = "on";
    inherit parallel;
    ctx-size = parallel * 262144;
    cache-type-k = "q8_0";
    cache-type-v = "q8_0";
    jinja = true;
    # Qwen3.8 thinking-mode sampling preset
    temp = 1.0;
    top-p = 0.95;
    top-k = 20;
  };

  # Same "--option value" rendering as the services.llama-cpp module.
  toArgs = lib.cli.toCommandLineShell (optionName: {
    option = "--${optionName}";
    sep = null;
    explicitBool = false;
  });

  # Runs in the foreground: closing the terminal stops the server. The
  # inhibitor keeps GNOME's idle suspend from cutting off LAN clients.
  launcher = pkgs.writeShellApplication {
    name = "llm-server";
    text = ''
      exec systemd-inhibit --what=sleep:idle --who=llm-server --why="LLM server running" \
        ${lib.getExe' llamaCpp "llama-server"} ${toArgs (settingsFor 2)}
    '';
  };
in
{
  # Build CUDA code only for the RTX 5090.
  nixpkgs.config.cudaCapabilities = [ "12.0" ];

  environment.systemPackages = [
    llamaCpp
    launcher
    (pkgs.makeDesktopItem {
      name = "llm-server";
      desktopName = "LLM Server";
      exec = "llm-server";
      terminal = true;
    })
  ];

  # Model and key must be readable by both alexander (launcher) and the
  # service's DynamicUser; the key only via the llm group.
  users.groups.llm = { };
  systemd.tmpfiles.rules = [
    "d /var/lib/llm 0755 root root -"
    "d /var/lib/llm/models 0755 root root -"
  ];

  networking.firewall.allowedTCPPorts = [ 8080 ];

  # Headless boot entry: no GDM, so both GPUs are fully free for the model.
  specialisation.llm.configuration = {
    system.nixos.tags = [ "llm" ];
    systemd.defaultUnit = lib.mkForce "multi-user.target";
    services.llama-cpp = {
      enable = true;
      package = llamaCpp;
      settings = settingsFor 3;
    };
    systemd.services.llama-cpp.serviceConfig.SupplementaryGroups = [ "llm" ];
  };
}
