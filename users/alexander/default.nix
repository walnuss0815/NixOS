{ config, pkgs, ... }:

{
  home.username = "alexander";
  home.homeDirectory = "/home/alexander";

  home.file.".face" = {
    source = ./img/face.jpg;
  };

  # link the configuration file in current directory to the specified location in home directory
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;

  # link all files in `./scripts` to `~/.config/i3/scripts`
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;   # link recursively
  #   executable = true;  # make all files executable
  # };

  # encode the file content in nix configuration file directly
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  xdg.configFile."mimeapps.list".force = true;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "org.mozilla.firefox.desktop";
      "x-scheme-handler/http" = "org.mozilla.firefox.desktop";
      "x-scheme-handler/https" = "org.mozilla.firefox.desktop";
      "x-scheme-handler/about" = "org.mozilla.firefox.desktop";
      "x-scheme-handler/unknown" = "org.mozilla.firefox.desktop";

      "application/pdf" = "org.gnome.Evince.desktop";

      "text/plain" = "org.gnome.TextEditor.desktop";
      "text/markdown" = "org.gnome.TextEditor.desktop";
      "text/x-shellscript" = "org.gnome.TextEditor.desktop";
      "application/x-shellscript" = "org.gnome.TextEditor.desktop";

      "image/jpeg" = "org.gnome.Loupe.desktop";
      "image/png" = "org.gnome.Loupe.desktop;";
      "image/gif" = "org.gnome.Loupe.desktop;";
      "image/webp" = "org.gnome.Loupe.desktop;";
      "image/tiff" = "org.gnome.Loupe.desktop;";
      "image/x-tga" = "org.gnome.Loupe.desktop;";
      "image/vnd-ms.dds" = "org.gnome.Loupe.desktop;";
      "image/x-dds" = "org.gnome.Loupe.desktop;";
      "image/bmp" = "org.gnome.Loupe.desktop;";
      "image/vnd.microsoft.icon" = "org.gnome.Loupe.desktop;";
      "image/vnd.radiance" = "org.gnome.Loupe.desktop;";
      "image/x-exr" = "org.gnome.Loupe.desktop;";
      "image/x-portable-bitmap" = "org.gnome.Loupe.desktop;";
      "image/x-portable-graymap" = "org.gnome.Loupe.desktop;";
      "image/x-portable-pixmap" = "org.gnome.Loupe.desktop;";
      "image/x-portable-anymap" = "org.gnome.Loupe.desktop;";
      "image/x-qoi" = "org.gnome.Loupe.desktop;";
      "image/svg+xml" = "org.gnome.Loupe.desktop;";
      "image/svg+xml-compressed" = "org.gnome.Loupe.desktop;";
      "image/avif" = "org.gnome.Loupe.desktop;";
      "image/heic" = "org.gnome.Loupe.desktop;";
      "image/jxl" = "org.gnome.Loupe.desktop;";
    };
  };

  # set cursor size and dpi for 4k monitor
  xresources.properties = {
    "Xcursor.size" = 16;
    "Xft.dpi" = 172;
  };

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    # here is some command line tools I use frequently
    # feel free to add your own or remove some of them

    # archives
    zip
    xz
    unzip
    p7zip

    # AI
    opencode
    opencode-claude-auth
    claude-code
    vscode-extensions.anthropic.claude-code

    # networking tools
    mtr # A network diagnostic tool
    iperf3
    dnsutils # `dig` + `nslookup`
    ldns # replacement of `dig`, it provide the command `drill`
    aria2 # A lightweight multi-protocol & multi-source command-line download utility
    socat # replacement of openbsd-netcat
    nmap # A utility for network discovery and security auditing
    ipcalc # it is a calculator for the IPv4/v6 addresses

    # misc
    cowsay
    file
    which
    tree
    gnused
    gnutar
    gawk
    zstd
    gnupg

    # nix related
    #
    # it provides the command `nom` works just like `nix`
    # with more details log output
    nix-output-monitor

    btop # replacement of htop/nmon
    iotop # io monitoring
    iftop # network monitoring

    # system call monitoring
    strace # system call monitoring
    ltrace # library call monitoring
    lsof # list open files

    # system tools
    sysstat
    lm_sensors # for `sensors` command
    ethtool
    pciutils # lspci
    usbutils # lsusb

    # development tools
    glab # Gitlab CLI
    ghorg # Clone GitHub orgs and Gitlab groups

    restic-browser
    restic

    firefox

  ];

  # This value determines the home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update home Manager without changing this value. See
  # the home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.05";

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
