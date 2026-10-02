{
  description = "walnuss0815 NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Pinned separately (not `follows`-ed to the unstable `nixpkgs` above)
    # so specific packages (e.g. bambu-studio, see users/alexander) can be
    # pulled from the stable release instead. The branch suffix here is
    # bumped automatically by Renovate (.github/renovate.json5) whenever a
    # new NixOS stable release ships; .github/workflows/renovate-update-lock.yml
    # then refreshes flake.lock on that PR.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      # Without this, nixos-hardware pulls in its own nixpkgs tarball,
      # adding a third (silently drifting) nixpkgs tree to flake.lock.
      # Its nixosModules.* are pure module functions evaluated against
      # each host's own pkgs, so following the root input changes nothing
      # that gets built - it just keeps the lock graph to two nixpkgs
      # (unstable + nixpkgs-stable).
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-stable, home-manager, nixos-hardware, nur, lanzaboote, disko }:

    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };

      pkgsStable = import nixpkgs-stable {
        inherit system;
        config = { allowUnfree = true; };
      };

    in
    {
      nixosConfigurations = {
        alexander-nb2 = nixpkgs.lib.nixosSystem {
          inherit system;

          modules = [
            ./hosts/alexander-nb2/configuration.nix
            nixos-hardware.nixosModules.lenovo-thinkpad-x280
            ./modules/system/gnome
            ./modules/system/docker
            ./modules/system/netbird
            ./modules/system/printing
            ./modules/system/nix-storage-optimisation
            ./modules/system/nix-cache
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
            lanzaboote.nixosModules.lanzaboote
            ./modules/system/gnome
            ./modules/system/docker
            ./modules/system/netbird
            ./modules/system/printing
            ./modules/system/nix-storage-optimisation
            ./modules/system/nix-cache
            ./modules/system/nix-ld
            ./modules/system/mdns
          ];
        };

        owhug-pc1 = nixpkgs.lib.nixosSystem {
          inherit system;

          modules = [
            ./hosts/owhug-pc1/configuration.nix
            nixos-hardware.nixosModules.common-cpu-amd
            nixos-hardware.nixosModules.common-cpu-amd-pstate
            nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
            nixos-hardware.nixosModules.common-pc-ssd
            nur.modules.nixos.default
            lanzaboote.nixosModules.lanzaboote
            disko.nixosModules.disko
            ./modules/system/gnome
            ./modules/system/docker
            ./modules/system/netbird
            ./modules/system/printing
            ./modules/system/nix-storage-optimisation
            ./modules/system/nix-cache
            ./modules/system/nix-ld
            ./modules/system/mdns
            ./modules/system/ninfer
          ];
        };
      };

      homeConfigurations = {
        alexander = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit pkgsStable; };

          modules = [
            nur.modules.homeManager.default
            ./users/alexander
            ./modules/user/gnome
            ./modules/user/firefox
            ./modules/user/shell
            ./modules/user/git
            ./modules/user/vscode
            ./modules/user/ai
            ./modules/user/bitwarden
          ];
        };
      };

      # `nix flake check` only evaluates standard outputs, which does not
      # include homeConfigurations, so build the home-manager generation
      # explicitly to cover it.
      checks.${system}.home-alexander =
        self.homeConfigurations.alexander.activationPackage;

      # `nix fmt`, also used by CI, so formatting always follows the pinned
      # nixpkgs instead of whatever the runner resolves.
      formatter.${system} = pkgs.nixfmt;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ nixfmt nil statix deadnix ];
      };
    };
}
