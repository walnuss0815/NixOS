{ pkgs, ... }: {
  programs.rbw = {
    enable = true;
    settings = {
      email = "walnuss0815@gmail.com";
      pinentry = pkgs.pinentry-gnome3;
    };
  };
}
