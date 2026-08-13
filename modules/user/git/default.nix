{ pkgs, config, ... }:
let
  name = "Alexander Weidemann";
  email = "walnuss0815@gmail.com";
  signingKeyValue = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP9agMLuqQcDPEzPnTTT48UYrsqgyvW3VtfG8JQW3wr2";
  signingKeyPath = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
  allowedSignersFile = "${config.home.homeDirectory}/.config/git/allowed_signers";
in {
  home.packages = with pkgs; [
    ghq
  ];
  home.file.".config/git/allowed_signers".text = "${email} ${signingKeyValue}\n";
  programs.git = {
    enable = true;
    settings = {
      ghq = {
        root = "~/Projects";
      };
      user = {
        inherit name;
        inherit email;
        signingkey = signingKeyPath;
      };
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = allowedSignersFile;
      commit.gpgsign = true;
      lfs.enable = true;
      alias = {
        co = "checkout";
        br = "branch";
        ci = "commit";
        st = "status";
        unstage = "reset HEAD --";
        up = "fetch --prune --all";
        graph = "log --oneline --graph --decorate";
        fpush = "push --force-with-lease";
        mr =
          "push --push-option=merge_request.create --push-option=merge_request.draft";
        wip = "commit --message='WIP'";
        track = "add --intent-to-add";
        tow = "pull --recurse-submodules=on-demand";
        irb = "rebase --interactive --autosquash";
        repo = "remote --verbose";
        fuck = "commit --fixup";
        pfuck = "commit --patch --fixup";
        fix = "commit --amend --no-edit";
        pfix = "commit --amend --no-edit --patch";
        hash = "rev-parse HEAD";
        sub = "submodule";
        edit = "commit --amend --only";
        cf = "diff-tree --no-commit-id --name-only";
        cfr = "cf -r";
        asq = "rebase --autosquash";
        cb = "rev-parse --abbrev-ref HEAD";
      };
      core.eol = "lf";
      core.autocrlf = false;
      merge.ff = "only";
      pull.ff = "only";
      push.autoSetupRemote = true;
      init.defaultBranch = "main";
      credential.helper = [ "oauth" "cache --timeout 21600" ];
    };
  };
}
