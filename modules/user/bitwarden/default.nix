{ pkgs, ... }:
let
  # Caches the master password in the GNOME Keyring after the first
  # manual unlock, so rbw stops prompting entirely afterwards. See
  # ../../../pkgs/rbw-pinentry-keyring for what this trades away.
  rbwPinentryKeyring = pkgs.callPackage ../../../pkgs/rbw-pinentry-keyring { };
in {
  home.packages = [ rbwPinentryKeyring ];

  programs.rbw = {
    enable = true;
    settings = {
      email = "walnuss0815@gmail.com";
      pinentry = rbwPinentryKeyring;
      lock_timeout = 43200;
    };
  };
}
