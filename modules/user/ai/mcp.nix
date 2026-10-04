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

      # Native binary (nixpkgs github-mcp-server) instead of the official
      # Docker image: no docker dependency, and auth is a PAT fetched
      # fresh from the Bitwarden vault via rbw (unlocked automatically
      # through the GNOME pinentry dialog if the vault is currently
      # locked), rather than the OAuth device/browser flow the docker image
      # used (which needed a fixed loopback callback port). The token never
      # touches the Nix store or disk.
      #
      # The rbw call itself no longer happens here: opencode (and
      # everything it spawns, including this server) runs under the nono
      # sandbox defined in ./opencode.nix, and ~/.cache/rbw holds the
      # *decrypted* vault cache - not something the sandbox should ever be
      # able to read. Instead, nono's session_hooks.before runs `rbw get`
      # host-privileged before the sandbox is applied and injects only the
      # resulting bare token as GITHUB_PERSONAL_ACCESS_TOKEN, which this
      # process then simply inherits.
      #
      # GITHUB_TOOLS is an exact allowlist instead of GITHUB_TOOLSETS:
      # every loaded tool's schema is sent with every model request, and
      # whole toolsets pulled in ~60 tools (plus a long Projects
      # instruction block) for a workflow that only needs CI logs, PRs,
      # commits and repo creation. With no toolsets set, the server loads
      # exactly these tools - so merge/delete/push/fork tools are not
      # merely gated by permissions, they do not exist in the session.
      # Approval rules for these live in ./opencode.nix ("github_*").
      github = {
        command = "${pkgs.github-mcp-server}/bin/github-mcp-server";
        args = [ "stdio" ];
        env = {
          "GITHUB_TOOLS" = builtins.concatStringsSep "," [
            # CI
            "actions_list"
            "actions_get"
            "get_job_logs"
            "actions_run_trigger"
            # Pull requests
            "list_pull_requests"
            "search_pull_requests"
            "pull_request_read"
            "create_pull_request"
            "update_pull_request"
            "add_issue_comment"
            # Commits
            "list_commits"
            "get_commit"
            "list_branches"
            # Repositories / helpers
            "create_repository"
            "get_me"
            "get_file_contents"
          ];
        };
      };

      # No nixpkgs package for these exact servers exists yet, so they are
      # packaged locally under ../../../pkgs (fetched from their published
      # npm tarballs and hash-pinned there) instead of fetched via `npx` at
      # every MCP-server startup. This makes them fully reproducible/
      # offline - no network fetch at runtime, no silent version drift,
      # and no dependency on the npm registry being reachable when
      # opencode starts. Bump the version pin in the respective
      # ../../../pkgs/<name>/default.nix deliberately after checking
      # release notes (and regenerating package-lock.json/npmDepsHash
      # where applicable).
      kubernetes = {
        command = "${pkgs.callPackage ../../../pkgs/kubernetes-mcp-server { }}/bin/kubernetes-mcp-server";
        args = [
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
        command = "${pkgs.callPackage ../../../pkgs/git-mcp-server { }}/bin/git-mcp-server";
      };
    };
  };
}
