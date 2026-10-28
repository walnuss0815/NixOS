# Settings shared by the interactive x86 desktop/laptop hosts: networking,
# keyboard layout, audio, zsh and the base system packages. Pairs with
# ../common and ../gnome.
{ pkgs, ... }:

{
  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  hardware.alsa.enablePersistence = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.zsh.enable = true;

  # Pinned in /etc/ssh/ssh_known_hosts, which (unlike ~/.ssh/known_hosts,
  # replaced on every UpdateHostKeys rewrite) the opencode sandbox can
  # always read. Keys from https://api.github.com/meta.
  programs.ssh.knownHosts = {
    "github.com-ed25519" = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };
    "github.com-ecdsa" = {
      hostNames = [ "github.com" ];
      publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=";
    };
    "github.com-rsa" = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=";
    };
  };

  users.users.alexander = {
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" ];
  };

  # Desktop/GUI applications (LibreOffice, browsers, chat, media) live in
  # home-manager (users/alexander/default.nix) instead: per-user apps
  # don't need a full `sudo nixos-rebuild switch` to add/remove/update, and
  # this keeps the system closure limited to what's actually needed
  # system-wide, consistent with the modules/system vs modules/user split
  # used elsewhere in this repo.
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl

    # Nix Home Manager
    home-manager
  ];
}
