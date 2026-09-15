{
  # cache.nixos.org (official Hydra) doesn't build unfree packages, so
  # things like bambu-studio always get built from source locally without
  # this. nix-community.cachix.org is a large, widely-trusted community
  # cache that already has it (and plenty of other unfree/community
  # packages) pre-built.
  nix.settings = {
    substituters = [ "https://nix-community.cachix.org" ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}
