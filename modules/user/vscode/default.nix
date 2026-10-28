{ pkgs, config, ... }: {
  programs.vscode = {
    enable = true;
    profiles = {
      default = {
        userSettings = {
          "update.showReleaseNotes" = false;
          "workbench.startupEditor" = "none";
          "explorer.confirmDelete" = false;
          "git.autofetch" = true;
          "git.confirmSync" = false;
          "git.terminalAuthentication" = false;
          "files.eol" = "\n";
          "files.insertFinalNewline" = true;
          "cSpell.language" = "en;en-US;de-DE";
          "editor.bracketPairColorization.enabled" = true;
          "editor.rulers" = [
            80
            125
          ];
          "git.suggestSmartCommit" = false;
          "editor.renderWhitespace" = "all";
          "window.titleBarStyle" = "custom";
          "update.mode" = "none";
          "editor.insertSpaces" = true;
          "editor.tabSize" = 2;
          "editor.detectIndentation" = true;
          "terminal.integrated.suggest.enabled" = false;
          "terminal.integrated.shellIntegration.enabled" = false;
          # Let ctrl+p reach opencode instead of opening Quick Open, while
          # keeping VS Code's terminal paste (ctrl+shift+v).
          "terminal.integrated.commandsToSkipShell" = [ "-workbench.action.quickOpen" ];
          "chat.disableAIFeatures" = true;
          "telemetry.telemetryLevel" = "off";
          "telemetry.feedback.enabled" = false;
          "workbench.enableExperiments" = false;
          "workbench.settings.enableNaturalLanguageSearch" = false;
          "redhat.telemetry.enabled" = false;
          "extensions.ignoreRecommendations" = true;
          "workbench.welcomePage.walkthroughs.openOnInstall" = false;
          "workbench.tips.enabled" = false;
          "explorer.confirmDragAndDrop" = false;
          "vs-kubernetes" = {
            "vs-kubernetes.suppress-kubectl-not-found-alerts" = true;
            "vs-kubernetes.suppress-helm-not-found-alerts" = true;
          };
          "extensions.allowed" = {
            "*" = true;
            "anthropic.claude-code" = false;
            "github.vscode-pull-request-github" = false;
          };
          "json.schemaDownload.trustedDomains" = {
            "https://json-schema.org/" = true;
            "https://json.schemastore.org/" = true;
            "https://www.schemastore.org/" = true;
            "https://docs.renovatebot.com/" = true;
          };
          "yaml.disableSchemaDetection" = [
            "**/.github/workflows/*.yml"
            "**/.github/workflows/*.yaml"
            "**/.gitea/workflows/*.yml"
            "**/.gitea/workflows/*.yaml"
            "**/.forgejo/workflows/*.yml"
            "**/.forgejo/workflows/*.yaml"
          ];
        };
        extensions = [
          pkgs.vscode-extensions.mkhl.direnv
          pkgs.vscode-extensions.oderwat.indent-rainbow
          pkgs.vscode-extensions.streetsidesoftware.code-spell-checker
        ];
      };
    };
  };
}
