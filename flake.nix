{
  description = "walnuss0815 NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    silentSDDM = {
      url = "github:uiriansan/SilentSDDM";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-hardware, nur, silentSDDM }:

    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };

    in {
      nixosConfigurations = {
        alexander-nb2 = nixpkgs.lib.nixosSystem {
          inherit system;

          modules = [
            ./hosts/alexander-nb2/configuration.nix
            nixos-hardware.nixosModules.lenovo-thinkpad-x280
            ./modules/system/gnome
            ./modules/system/docker
            ./modules/system/tailscale
            ./modules/system/netbird
            ./modules/system/printing
            ./modules/system/nix-storage-optimisation
            ./modules/system/nix-ld
          ];
        };

        owhug-nb1 = nixpkgs.lib.nixosSystem {
          inherit system;

          modules = [
            ./hosts/owhug-nb1/configuration.nix
            nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen2
            nixos-hardware.nixosModules.common-pc-laptop-ssd
            nur.modules.nixos.default
            silentSDDM.nixosModules.default
            ./modules/system/gnome
            ./modules/system/docker
            ./modules/system/netbird
            ./modules/system/printing
            ./modules/system/nix-storage-optimisation
            ./modules/system/nix-ld
          ];
        };
      };

      homeConfigurations = {
        alexander = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            ./users/alexander
            ./modules/user/gnome
            ./modules/user/shell
            ./modules/user/git
            ./modules/user/vscode
            ./modules/user/ai
          ];
        };
      };
    };
}
