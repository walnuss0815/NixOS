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
