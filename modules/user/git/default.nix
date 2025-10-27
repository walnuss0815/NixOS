{ pkgs, config, ... }: {
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Alexander Weidemann";
        email = "walnuss0815@gmail.com";
      };
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
