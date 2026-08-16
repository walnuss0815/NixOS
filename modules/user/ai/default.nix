{ pkgs, config, ... }: {
  home.packages = [ (pkgs.callPackage ../../../pkgs/claude-swap { }) ];

  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    extraPackages = with pkgs; [
      nodejs_24
      libnotify
    ];
    tui = {
      attention = {
        enabled = true;
      };
    };

    settings = {
      permission = {
        external_directory = {
          "/nix/store/**" = "allow";
        };
        read = {
          "/nix/store/**" = "allow";
        };
        edit = {
          "/nix/store/**" = "deny";
        };

        # Shell access: ask by default, allow common read-only commands
        # without prompting, and hard-deny irreversible footguns. Explicit
        # "deny" rules stay enforced even under `opencode --auto`, unlike
        # "ask" rules which get auto-approved in that mode.
        bash = {
          "*" = "allow";

          "git status*" = "allow";
          "git diff*" = "allow";
          "git log*" = "allow";
          "git show*" = "allow";
          "ls*" = "allow";
          "cat*" = "allow";
          "rg *" = "allow";
          "grep *" = "allow";
          "find *" = "allow";

          "rm -rf *" = "deny";
          "dd *" = "deny";
          "mkfs*" = "deny";
          "shutdown*" = "deny";
          "reboot*" = "deny";
          "systemctl poweroff*" = "deny";
          "systemctl reboot*" = "deny";
        };

        # Globally configured MCP servers (programs.mcp.servers below,
        # merged into opencode via enableMcpIntegration). MCP tools are
        # namespaced "<server>_<tool>" (our config key, "_", then the
        # tool's own name exactly as the upstream server defines it).
        #
        # Rules of thumb applied per the upstream tool docs, most
        # specific first:
        #   - read-only lookups                         -> allow
        #   - anything that can return secret/credential
        #     material (k8s Secrets, kubeconfig, etc.)   -> ask
        #   - create/modify/delete operations            -> ask
        # Anything not explicitly listed below (including tools added by
        # a future server version) falls through to that server's "ask"
        # catch-all rather than an unreviewed "allow". Nix's JSON
        # serializer emits attrset keys alphabetically regardless of the
        # order written here, but "*" sorts before any letter/digit, so
        # each catch-all still resolves before its own specific
        # overrides ("last match wins").

        # mcp-nixos (github:utensils/mcp-nixos): exactly 2 tools, `nix`
        # and `nix_versions`, both pure query/search against public
        # NixOS/nixpkgs metadata APIs. No create/update/delete capability
        # exists in this server at all, so a blanket allow is safe.
        "nixos_*" = "allow";

        # kubernetes-mcp-server (github:containers/kubernetes-mcp-server).
        # Only the default "config" + "core" toolsets are enabled here
        # (no --toolsets flag set), so helm/kcp/kiali/kubevirt/netobserv/
        # tekton tools aren't exposed; if any of those get enabled later
        # they fall through to "ask" until reviewed.
        "kubernetes_*" = "ask";
        # config toolset - read-only
        "kubernetes_configuration_contexts_list" = "allow";
        "kubernetes_targets_list" = "allow";
        # configuration_view returns the kubeconfig, which can embed
        # client certs/tokens for cluster auth -> treated like
        # credential material, stays on the "ask" catch-all.
        # core toolset - read-only, typed to Pod/Node/Namespace/Event,
        # cannot return a Secret object
        "kubernetes_namespaces_list" = "allow";
        "kubernetes_projects_list" = "allow";
        "kubernetes_events_list" = "allow";
        "kubernetes_nodes_log" = "allow";
        "kubernetes_nodes_stats_summary" = "allow";
        "kubernetes_nodes_top" = "allow";
        "kubernetes_pods_list" = "allow";
        "kubernetes_pods_list_in_namespace" = "allow";
        "kubernetes_pods_get" = "allow";
        "kubernetes_pods_top" = "allow";
        "kubernetes_pods_log" = "allow";
        # Stays on "ask": pods_delete/pods_exec/pods_run (delete/exec/
        # create); resources_get/resources_list (generic - can return
        # ANY resource kind including v1 Secret, which is exactly the
        # "always ask before reading secrets" case); resources_create_
        # or_update, resources_delete, resources_scale (modify/create/
        # delete).

        # @cyanheads/git-mcp-server (github:cyanheads/git-mcp-server), 28
        # tools. The server's own tool names already start with "git_",
        # so namespacing with our "git" server key doubles the prefix
        # (e.g. "git_git_status"). Double-check the exact literal names
        # against what actually shows up in an approval prompt or
        # `opencode mcp list` and adjust if this guess is off - the "ask"
        # catch-all is the safety net either way.
        "git_*" = "ask";
        # History & inspection - read-only, never touches the working tree
        "git_git_status" = "allow";
        "git_git_diff" = "allow";
        "git_git_log" = "allow";
        "git_git_show" = "allow";
        "git_git_blame" = "allow";
        "git_git_reflog" = "allow";
        "git_git_changelog_analyze" = "allow";
        # fetch only updates remote-tracking refs, it never touches your
        # current branch/working tree (unlike pull, which merges)
        "git_git_fetch" = "allow";
        # session/context bookkeeping only, no repository mutation
        "git_git_set_working_dir" = "allow";
        "git_git_clear_working_dir" = "allow";
        "git_git_wrapup_instructions" = "allow";
        # Stays on "ask": git_init/git_clone (create); git_add/git_commit
        # (modify); git_clean/git_reset (destructive); git_branch/
        # git_tag/git_remote/git_stash/git_worktree (each bundles list+
        # create+delete in one tool, treated conservatively); git_
        # checkout/git_merge/git_rebase/git_cherry_pick (modify); git_
        # pull/git_push (modify/publish).

        # ssh-mcp (github:tufantunc/ssh-mcp) v2 - its README tool table
        # already marks each tool readOnly/destructive; mirrored
        # directly here.
        "ssh_*" = "ask";
        "ssh_list-connections" = "allow";
        "ssh_list-sessions" = "allow";
        "ssh_open-session" = "allow"; # not marked destructive upstream
        "ssh_read-session-output" = "allow";
        "ssh_read-command" = "allow"; # server-enforced read-only allowlist
        "ssh_sftp-download" = "allow";
        # Stays on "ask": close-session, run-command (arbitrary remote
        # command execution), privileged-command (sudo), sftp-upload,
        # signal-process - all marked destructive/mutating upstream.
      };
      "plugin" = [
        "opencode-claude-auth@latest"
        "opencode-notify@0.3.1"
      ];
      "provider" = {
        "ollama" = {
          "npm" = "@ai-sdk/openai-compatible";
          "name" = "Ollama (local)";
          "options" = {
            "baseURL" = "http://192.168.10.9:11434/v1";
          };
          "models" = {
            "qwen3.5:9b" = {
              "name" = "qwen3.5:9b";
            };
            "qwen3.6:35b-a3b" = {
              "name" = "qwen3.6:35b-a3b";
            };
          };
        };
        "rpp-ai-proxy" = {
          "npm" = "@ai-sdk/openai-compatible";
          "name" = "RPP AI Proxy";
          "options" = {
            "baseURL" = "https://ai-proxy.rpp.gmbh/v1";
          };
          "models" = {
            "Gemini 3.5 Flash" = {
              "name" = "Gemini 3.5 Flash";
            };
            "Gemini 3.5 Flash Lite" = {
              "name" = "Gemini 3.5 Flash Lite";
            };
            "Gemini 3.1 Flash Lite" = {
              "name" = "Gemini 3.1 Flash Lite";
            };
            "gemini-2.5-pro" = {
              "name" = "gemini-2.5-pro";
            };
            "Claude Sonnet 5" = {
              "name" = "Claude Sonnet 5";
            };
            "Claude Opus 4.8" = {
              "name" = "Claude Opus 4.8";
            };
            "Claude Haiku 4.5" = {
              "name" = "Claude Haiku 4.5";
            };
            "Claude Fable 5" = {
              "name" = "Claude Fable 5";
            };
            "Mistral Small" = {
              "name" = "Mistral Small";
            };
            "Mistral Medium" = {
              "name" = "Mistral Medium";
            };
            "Mistral Large" = {
              "name" = "Mistral Large";
            };
            "Devstral 2" = {
              "name" = "Devstral 2";
            };
            "Devstral Small" = {
              "name" = "Devstral Small";
            };
            "Qwen Turbo" = {
              "name" = "Qwen Turbo";
            };
            "Qwen Plus" = {
              "name" = "Qwen Plus";
            };
            "Qwen Max" = {
              "name" = "Qwen Max";
            };
            "Qwen 3 32B" = {
              "name" = "Qwen 3 32B";
            };
          };
        };
      };
    };
    skills = {
      code-review = ./skills/code-review.md;
      git-commit = ./skills/git-commit.md;
      create-agents-file = ./skills/create-agents-file.md;
    };
    context = ./context.md;
  };

  # opencode-notify (npm plugin listed above) is deliberately quiet by
  # default: it only pops a banner on permission asks / questions / errors.
  # With the permissive permission rules above the agent almost never asks,
  # so nothing ever shows up -- including when a long task finally finishes.
  # The "agent done, waiting for input" alert is behind `notifyOnIdle`, which
  # the plugin ships disabled, so it must be enabled here or it never fires.
  # Delivery uses notify-send (libnotify is on opencode's PATH via
  # programs.opencode.extraPackages); the preferred node-dbus-notifier
  # backend can't compile under Nix (missing dbus dev headers at bun install)
  # and the plugin falls back to notify-send, which is enough for non-actioned
  # popups.
  xdg.configFile."opencode/opencode-notify.json".text = builtins.toJSON {
    notifyOnIdle = true;
  };

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
        args = [ "-y" "kubernetes-mcp-server@0.0.66" ];
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
