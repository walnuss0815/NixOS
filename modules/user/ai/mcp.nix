# MCP (Model Context Protocol) server definitions. These servers are
# merged into opencode's config via programs.opencode.enableMcpIntegration
# (see ./opencode.nix); the per-tool permission rules for them live next
# to that setting.
{ pkgs, ... }: {
  programs.mcp = {
    enable = true;
    servers = {
      # Packaged in nixpkgs, so this is fully reproducible/offline: no
      # network fetch at runtime and no untracked version drift.
      nixos = {
        command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
      };

      # As of now there is no real alternative to run the GitHub MCP with OAuth
      # (the nixpkgs build doesn't inject the official OAuth app credentials).
      github = {
        command = "docker";
        args = [
          "run"
          "-i"
          "--rm"
          "-p"
          "127.0.0.1:8085:8085"
          "-e"
          "GITHUB_OAUTH_CALLBACK_PORT"
          "ghcr.io/github/github-mcp-server:v1.9.0"
        ];
        env = {
          "GITHUB_OAUTH_CALLBACK_PORT" = "8085";
          "GITHUB_TOOLSETS" = "default,actions,gists,projects";
        };
      };

      # No nixpkgs package for these exact servers exists yet, so they are
      # still fetched via npx at runtime. Pinned to an exact version
      # (instead of `@latest`) so the server doesn't silently change
      # behavior underneath us; bump deliberately after checking release
      # notes.
      kubernetes = {
        command = "npx";
        args = [
          "-y"
          "kubernetes-mcp-server@0.0.66"
          "--config"
          # Server-side deny list of GroupVersionKinds. OpenCode's
          # permission rules only match tool names, never arguments, so
          # "get Volume vs. get Secret" cannot be distinguished
          # client-side. This TOML blocks these GVKs before any handler
          # runs, so no tool (including the generic resources_get/list)
          # can ever return them - and unlike a client "ask"/"deny",
          # it is not auto-approved away under `opencode --auto`.
          # Interpolated so the resulting store path is a plain string
          # (programs.mcp.servers.*.args is typed listOf string).
          "${pkgs.writeText "kubernetes-mcp-server.toml" ''
            # Kubernetes Secrets may embed tokens/credentials (incl.
            # service-account and dockerconfigjson types) -> hard block.
            [[denied_resources]]
            group = ""
            version = "v1"
            kind = "Secret"
          ''}"
        ];
      };
      git = {
        command = "npx";
        args = [ "-y" "@cyanheads/git-mcp-server@2.15.1" ];
      };
      ssh = {
        command = "npx";
        args = [ "-y" "ssh-mcp@2.1.0" ];
      };
    };
  };
}
