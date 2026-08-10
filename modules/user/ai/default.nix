{ pkgs, config, ... }: {
  programs.opencode = {
    enable = true;
    web.enable = true;
    enableMcpIntegration = true;
    extraPackages = with pkgs; [
      nodejs_24
    ];
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
      };
      "plugin" = [
        "opencode-claude-auth@latest"
      ];
      "provider" = {
        "ollama" = {
          "npm" = "@ai-sdk/openai-compatible";
          "name" = "Ollama (local)";
          "options" = {
            "baseURL" = "http://192.168.10.5:11434/v1";
          };
          "models" = {
            "qwen3.5:9b" = {
              "name" = "qwen3.5:9b";
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
  };

  programs.mcp = {
    enable = true;
    servers = {
      # Packaged in nixpkgs, so this is fully reproducible/offline: no
      # network fetch at runtime and no untracked version drift.
      nixos = {
        command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
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
