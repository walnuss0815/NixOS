# rpp-github-runner1: self-hosted GitHub Actions runner VM on server1
# (Proxmox). Runner, Docker and update settings are shared by all runner
# hosts and live in modules/system/github-runner. See ./README.md for the
# VM settings and the install runbook.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    # Declarative disk layout, used by nixos-anywhere during install;
    # generates fileSystems."/" and the GRUB install device.
    ./disko.nix
  ];

  networking.hostName = "rpp-github-runner1";

  # Static address on VLAN 130 (tagged on the Proxmox NIC). Matching on
  # en* keeps this independent of the exact interface name (ens18 on
  # Proxmox) and leaves Docker's veth/bridge interfaces alone.
  networking.useDHCP = false;
  networking.useNetworkd = true;
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "en*";
    address = [ "192.168.13.12/24" ];
    gateway = [ "192.168.13.254" ];
    dns = [ "192.168.13.254" ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.11"; # Did you read the comment?
}
