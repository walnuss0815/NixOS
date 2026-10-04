# opencode configuration: global tool settings (permissions, providers,
# plugins), skills and context, plus the packaged claude-swap wrapper and
# the opencode-notifier plugin config. The MCP servers this talks to are
# defined in ./mcp.nix and merged in below via enableMcpIntegration.
#
# Filesystem sandboxing: programs.opencode.package below is swapped for a
# wrapper that runs the real opencode binary under `nono` (Landlock-enforced
# kernel sandbox - see nono.sh/docs). This replaces the plain `opencode` on
# PATH globally, so it can never be launched unsandboxed by accident.
# `permission` config further down stays as an approval-workflow layer on
# top of that; nono is the actual security boundary
# (in particular, bash: "*" = "allow" below is safe precisely because nono
# constrains what that shell can touch at the kernel level).
{ pkgs, config, ... }:
let
  # Kernel-enforced (Landlock) sandbox profile for opencode. Modeled on
  # nono's own bundled "opencode" preset (see nono.sh/docs/cli/features/
  # profiles-groups#opencode) but hand-written here because the nixpkgs-
  # pinned nono version predates that bundled preset, and adjusted for
  # NixOS: the upstream preset's "opencode_linux" group only grants
  # ~/.opencode/bin (the curl-installer layout), which is irrelevant here
  # since opencode and every tool it shells out to (git, rg, kubectl, ...)
  # live under unpredictable /nix/store/<hash>-<name>/bin paths instead.
  # "nix_runtime" is the group that actually covers that (verified via
  # `nono profile groups nix_runtime`: grants read on /nix/store,
  # /run/current-system/sw, /etc/profiles/per-user and ~/.nix-profile) -
  # without it, every bash-tool invocation of a store-packaged binary
  # fails with "directory is not readable inside the sandbox". Grants:
  # CWD (via --allow-cwd in the wrapper below), opencode's own XDG state/
  # config/cache/data dirs, $TMPDIR (opencode writes editor-buffer/clipboard
  # temp files with unpredictable names there). No other fixed
  # directories are granted - add project-specific extras via a
  # ".opencode-sandbox.jsonc"/".json" file in the project root instead (see
  # the wrapper script below and `nono profile guide`).
  #
  # $XDG_STATE_HOME/opencode is load-bearing, not just a persistence
  # nicety: Flock's lock root is <state>/locks (packages/core/src/
  # global.ts), and every Npm.add() plugin install and the models.dev
  # catalog refresh take a lock there. If the directory is denied, those
  # mkdir/rename calls fail with EACCES, which breaks plugin installation
  # and leaves the model catalog stale. The TUI also keeps model.json,
  # kv.json, session.json and prompt history there; if it is denied, the
  # saved model history cannot be read or updated.
  #
  # Caveat for OpenCode 2: its CLI (packages/cli) starts a background
  # daemon that keeps a password in <state>/password and its endpoint in
  # <state>/server.json. The grant above makes both readable to the
  # agent, and nono cannot carve them out (it refuses to start when a
  # deny path sits inside an allowed directory). The installed 1.18.x has
  # no daemon, so this does not apply today; revisit this grant before
  # upgrading.
  nonoProfile = {
    meta = {
      name = "opencode-nixos";
      version = "1.0.0";
      description = "Kernel-enforced (Landlock) sandbox for opencode.";
    };
    groups.include = [
      "user_caches_linux"
      "node_runtime"
      "nix_runtime"
      "git_config"
      "unlink_protection"
    ];
    workdir.access = "readwrite";
    filesystem = {
      allow = [
        "$XDG_STATE_HOME/opencode"
        "$XDG_CONFIG_HOME/opencode"
        "$XDG_CACHE_HOME/opencode"
        "$XDG_DATA_HOME/opencode"
        "$XDG_DATA_HOME/opentui"
        "$TMPDIR"
      ];
      # Single-file, not the whole ~/.claude directory: the
      # opencode-claude-auth plugin (in the plugin list below) reads its
      # Claude Code OAuth credentials from exactly this file on Linux
      # (README: "~/.claude/.credentials.json (fallback, works on all
      # platforms)") and rewrites it in place whenever it refreshes a
      # near-expiry token - re-read every ~30s in-process for the whole
      # session, so unlike the GitHub token this can't be moved to a
      # one-shot pre-session hook. The rest of ~/.claude/ (other projects'
      # conversation transcripts, daemon control key, session keys) stays
      # outside the sandbox entirely.
      allow_file = [
        "$HOME/.claude/.credentials.json"
      ];
      # Read-only exceptions to the (required, otherwise unconditional)
      # deny_credentials group, which blocks all of ~/.ssh so an agent can
      # never read a private key. This carves out *only*:
      #  - every public key (~/.ssh/*.pub, which covers the commit-signing
      #    key referenced by signingKeyPath in ../git/default.nix) so
      #    `git commit`/`ssh-keygen -Y sign` can embed it in the signature.
      #    Private keys have no .pub suffix, so they never match, stay
      #    unreadable and never enter the sandbox. The glob is expanded once
      #    at sandbox start (Linux), so a .pub created mid-session only
      #    becomes readable after restarting opencode. Goes in `read` since
      #    `read_file` takes no wildcards.
      #  - known_hosts, read-only, so sandboxed ssh/git can verify already
      #    trusted hosts. Deliberately not writable: a compromised agent
      #    could otherwise plant host keys that stay trusted outside the
      #    sandbox. New hosts must be added from outside opencode.
      # bypass_protection lifts the deny rule for exactly these paths - see
      # "Profile with deny overrides" in `nono profile guide` - it does not
      # grant access by itself, hence the matching read/read_file entries.
      read = [
        "$HOME/.ssh/*.pub"
      ];
      read_file = [
        "$HOME/.ssh/known_hosts"
      ];
      bypass_protection = [
        "$HOME/.ssh/*.pub"
        "$HOME/.ssh/known_hosts"
      ];
      # Connect-only: lets the opencode-notifier plugin reach the D-Bus
      # session bus (libnotify/notify-send) and PipeWire's pulse-compat
      # socket (paplay) for its desktop notification/sound events, and lets
      # git/ssh-keygen request a commit signature from GNOME Keyring's
      # ssh-agent (gcr) - the same keyring trust boundary already relied on
      # for rbw auto-unlock (see ../bitwarden). None of these grant bind(),
      # so this cannot be used to stand up a rogue service, and the actual
      # private key material never crosses into the sandbox - only a
      # signature computed by the agent on the other end of the socket.
      unix_socket = [
        "$XDG_RUNTIME_DIR/bus"
        "$XDG_RUNTIME_DIR/pulse/native"
        "$XDG_RUNTIME_DIR/gcr/ssh"
      ];
    };
    network.block = false; # LLM provider APIs and MCP servers (GitHub, k8s) need it
    session_hooks.before = {
      # Runs host-privileged, before the sandbox is applied - this is
      # deliberately outside the profile's filesystem grants above. It
      # fetches the GitHub MCP server's token and the owhug-pc1 NInfer API
      # key from the Bitwarden vault via rbw (possibly prompting through
      # GNOME pinentry) and hands only the resulting bare values to the
      # sandboxed process as env vars. This means the sandbox itself never
      # needs (and never gets) read access to ~/.cache/rbw - which holds
      # the *decrypted* vault cache - or to the pinentry/D-Bus machinery
      # that unlocking it requires. See ./mcp.nix for the github MCP
      # server and the "owhug-pc1" provider below, which just read these
      # env vars.
      script = "${config.xdg.configHome}/nono/hooks/fetch-tokens.sh";
      timeout_secs = 20;
    };
  };

  # Wraps the real opencode binary so that plain `opencode` invocations
  # always run under the nono sandbox above. Detects an optional
  # ".opencode-sandbox.jsonc"/".json" file in the launch directory and, if
  # present, layers it on top via nono's native --extends mechanism - this
  # is how a specific project can be granted extra paths beyond its own
  # CWD without touching this Nix config.
  sandboxedOpencode = pkgs.writeShellApplication {
    name = "opencode";
    runtimeInputs = [
      pkgs.nono
      pkgs.coreutils
    ];
    meta.mainProgram = "opencode";
    text = ''
      # libpulse mkdir()s $XDG_RUNTIME_DIR/pulse before connecting and Landlock
      # denies it (the profile grants the socket, not its parent dir), so paplay
      # fails. Naming the socket directly skips that check.
      if [ -z "''${PULSE_SERVER:-}" ] && [ -S "''${XDG_RUNTIME_DIR:-}/pulse/native" ]; then
        export PULSE_SERVER="unix:''${XDG_RUNTIME_DIR}/pulse/native"
      fi

      # Keep npm's cache inside the already-granted opencode cache dir. The
      # node_runtime group only gives read access to ~/.npm, so plugin
      # installs (Npm.add) would otherwise fail staging downloads in
      # ~/.npm/_cacache/tmp. A pre-set npm_config_cache still wins.
      export npm_config_cache="''${npm_config_cache:-''${XDG_CACHE_HOME:-$HOME/.cache}/opencode/npm}"

      # nono refuses to grant $HOME or its ancestors (Landlock can't enforce the
      # credential denies beneath them), so start in a fixed private dir instead.
      # It must be stable: opencode scopes sessions by directory, so a random dir
      # per launch makes sessions started in ~ unrecoverable. It lives under the
      # already-granted opencode data dir, so no extra sandbox grant is needed.
      workdir_args=()
      case "$PWD" in
        / | "$(dirname "$HOME")" | "$HOME")
          home_workdir="''${XDG_DATA_HOME:-$HOME/.local/share}/opencode/home"
          mkdir -p "$home_workdir"
          workdir_args=(--workdir "$home_workdir")
          ;;
      esac

      extends_args=()
      for f in .opencode-sandbox.jsonc .opencode-sandbox.json; do
        if [ -f "$f" ]; then
          extends_args+=(--extends "$PWD/$f")
          break
        fi
      done
      exec nono run --profile opencode-nixos "''${workdir_args[@]}" "''${extends_args[@]}" --allow-cwd -- ${pkgs.opencode}/bin/opencode "$@"
    '';
  };
in
{
  home.packages = [
    (pkgs.callPackage ../../../pkgs/claude-swap { })
    # For manual profile inspection/debugging: `nono profile show
    # opencode-nixos`, `nono why --path ... --op ...`, etc.
    pkgs.nono
  ];

  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    package = sandboxedOpencode;
    extraPackages = with pkgs; [
      nodejs_24
      libnotify
      # paplay: audio backend opencode-notifier uses to play event sounds
      # on Linux (talks to pipewire-pulse). Without one of paplay/aplay/
      # mpv/ffplay on PATH the plugin still notifies but stays silent.
      pulseaudio
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

        # Shell access: allow everything without prompting, since the nono
        # sandbox (see the header) is the actual boundary, and hard-deny a
        # few footguns as a tripwire. These are plain pattern matches on
        # the command line and are trivially bypassed (`rm -fr`,
        # `/bin/rm ...`), so they are not a security control. Explicit
        # "deny" rules stay enforced even under `opencode --auto`.
        bash = {
          "*" = "allow";

          "kubectl*" = "deny";
          "rm -rf *" = "deny";
          "dd *" = "deny";
          "mkfs*" = "deny";
          "shutdown*" = "deny";
          "reboot*" = "deny";
          "systemctl poweroff*" = "deny";
          "systemctl reboot*" = "deny";
        };

        # Globally configured MCP servers (programs.mcp.servers in
        # ./mcp.nix, merged into opencode via enableMcpIntegration). MCP
        # tools are namespaced "<server>_<tool>" (our config key, "_",
        # then the tool's own name exactly as the upstream server defines
        # it).
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
        "kubernetes_nodes_stats_summary" = "allow";
        "kubernetes_nodes_top" = "allow";
        "kubernetes_pods_list" = "allow";
        "kubernetes_pods_list_in_namespace" = "allow";
        "kubernetes_pods_get" = "allow";
        "kubernetes_pods_top" = "allow";
        # pods_log/nodes_log deliberately stay on the "ask" catch-all:
        # application and node logs routinely contain tokens, connection
        # strings or env dumps, and denied_resources cannot filter log
        # content the way it blocks Secret objects.
        # Generic get/list are safe to allow now: the server-side
        # `denied_resources` config (`--config` in ./mcp.nix) hard-blocks
        # v1 Secret before any handler runs, so these two tools can never
        # return credential material no matter what kind/args the client
        # passes. OpenCode's permission rules only match on tool names, so
        # this is the only place a per-resource-type distinction can be
        # enforced.
        "kubernetes_resources_get" = "allow";
        "kubernetes_resources_list" = "allow";
        # Stays on "ask": pods_log/nodes_log (may leak credentials, see
        # above); pods_delete/pods_exec/pods_run (delete/exec/create);
        # resources_create_or_update, resources_delete, resources_scale
        # (modify/create/delete).

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

        # github-mcp-server (github:github/github-mcp-server). Only the
        # GITHUB_TOOLS allowlist in ./mcp.nix is loaded at all; tools
        # outside it (merge, delete, push, fork, ...) do not exist in the
        # session. Of the loaded ones, read-only lookups are allowed and
        # everything else falls through to the "ask" catch-all.
        "github_*" = "ask";
        "github_actions_list" = "allow";
        "github_actions_get" = "allow";
        "github_get_job_logs" = "allow";
        "github_list_pull_requests" = "allow";
        "github_search_pull_requests" = "allow";
        "github_pull_request_read" = "allow";
        "github_list_commits" = "allow";
        "github_get_commit" = "allow";
        "github_list_branches" = "allow";
        "github_get_me" = "allow";
        "github_get_file_contents" = "allow";
        # Stays on "ask": actions_run_trigger (re-run/cancel workflows);
        # create_pull_request, update_pull_request, add_issue_comment
        # (publish on GitHub); create_repository (create).
      };
      # Both plugins are pinned to an exact version rather than @latest.
      # opencode caches each plugin under a directory keyed by this literal
      # spec string, with its own lockfile inside, so "@latest" does not
      # track anything: it resolves once on first install and then stays
      # frozen, with the resolved version recorded only in ~/.cache. That
      # makes it a per-machine accident - a fresh host, or a cleared cache,
      # resolves against whatever npm serves that day, so hosts can silently
      # end up on different versions. Pinning here keeps them identical and
      # puts the version under review. Bumps come from Renovate (see
      # .github/renovate.json5).
      "plugin" = [
        "opencode-claude-auth@2.2.1"
        "@mohak34/opencode-notifier@0.7.0"
      ];
      "provider" = {
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
        # owhug-pc1's NInfer server, serving an abliterated (uncensored)
        # Qwen3.8-27B NVFP4 artifact. See hosts/owhug-pc1/NINFER-SETUP.md
        # for the server-side setup and why this replaced the official
        # artifact. The API key (same value as owhug-pc1's
        # /var/lib/ninfer/api-key.txt) lives in the Bitwarden vault as
        # "owhug-pc1-ninfer-key" and is injected as an env var by the nono
        # session hook (fetch-tokens.sh below): a {file:...} reference
        # can't work here, since nono's required deny_credentials group
        # blocks ~/.secrets and similar dirs inside the sandbox. If the
        # vault entry is missing, the env var resolves to "" and only this
        # provider fails (401); opencode itself still starts.
        "owhug-pc1" = {
          "npm" = "@ai-sdk/openai-compatible";
          "name" = "owhug-pc1 (Qwen3.8-27B, NVFP4, uncensored)";
          "options" = {
            "baseURL" = "http://owhug-pc1.local:8080/v1";
            "apiKey" = "{env:OWHUG_PC1_NINFER_API_KEY}";
          };
          "models" = {
            "qwen3.8-27b" = {
              "name" = "Qwen3.8-27B abliterated (owhug-pc1, NVFP4+MTP)";
              "limit" = {
                # Matches the server's actual --max-context (see
                # hosts/owhug-pc1/configuration.nix's
                # services.ninfer.extraFlags). --vision is disabled there
                # (not needed for this use case); context is trimmed below
                # the native 262144 ceiling to fit the 32GB card alongside
                # this artifact's weights.
                "context" = 245760;
                "output" = 65536;
              };
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

  # opencode-notifier (@mohak34/opencode-notifier) sends desktop
  # notifications and plays sounds for permission/completion/error/question
  # events. Unlike opencode-notify it plays sounds natively on Linux: the
  # bundled sounds are fed through paplay (on opencode's PATH via
  # programs.opencode.extraPackages), no notify-send hint tricks needed.
  # `complete` fires by default, so long tasks end with a "Session has
  # finished" alert + sound (the old notifyOnIdle workaround is gone).
  # GNOME has no focus-detection API, so `suppressWhenFocused` has no
  # effect here (the compositor is unsupported -> always notify). It is
  # kept so focus suppression applies if that ever changes. Only the
  # global switches and Linux notification grouping are configured;
  # every other option keeps the plugin's defaults.
  xdg.configFile."opencode/opencode-notifier.json".text = builtins.toJSON {
    suppressWhenFocused = true;
    sound = true;
    notification = true;
    linux = {
      grouping = true;
    };
  };

  # nono sandbox profile + session hook (see the `let` block above for the
  # rationale). Declarative and Nix-managed: nono also supports an
  # interactive "save denied paths to profile" prompt after a run, but
  # accepting that would write outside of this config, so don't - port any
  # genuinely-needed paths it surfaces into nonoProfile above instead.
  xdg.configFile."nono/profiles/opencode-nixos.json".text = builtins.toJSON nonoProfile;

  xdg.configFile."nono/hooks/fetch-tokens.sh" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Runs host-privileged via nono's session_hooks.before (see nonoProfile
      # above), i.e. entirely outside the opencode sandbox. Fetches secrets
      # from the Bitwarden vault (rbw, unlocked via GNOME pinentry if
      # needed) and exports only the resulting bare values into the
      # sandboxed process's environment.
      set -eu

      # Required: ./mcp.nix's github MCP server reads this directly.
      token="$(${pkgs.rbw}/bin/rbw get github-mcp-server)"
      printf 'GITHUB_PERSONAL_ACCESS_TOKEN=%s\n' "$token" >> "$NONO_ENV_FILE"

      # Best-effort: API key for the "owhug-pc1" NInfer provider. A missing
      # vault entry only disables that provider instead of blocking startup.
      if ninfer_key="$(${pkgs.rbw}/bin/rbw get owhug-pc1-ninfer-key 2>/dev/null)"; then
        printf 'OWHUG_PC1_NINFER_API_KEY=%s\n' "$ninfer_key" >> "$NONO_ENV_FILE"
      fi
    '';
  };
}
