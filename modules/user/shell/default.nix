{ pkgs, config, ... }: {
  home.packages = with pkgs; [
    fastfetch
    nnn # terminal file manager
  ];

  programs.direnv = {
    enable = true;
    nix-direnv = { enable = true; };
  };

  programs.pay-respects = { enable = true; };

  programs.vim = {
    enable = true;
    defaultEditor = true;
    plugins = with pkgs.vimPlugins; [
      vim-lexical
      vim-fugitive
    ];
    extraConfig = ''
      set spell
      set spelllang=en
    '';
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "direnv" ];
      theme = "robbyrussell";
    };

    shellAliases = {
      ll = "ls -alh";
    };

    history.size = 10000;
    history.path = "${config.xdg.dataHome}/zsh/history";
  };
}
