{
  description = "Nyx - an opinionated, security-first NixOS desktop";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Declarative secrets. Nothing plaintext in the repo.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secure Boot with your own keys. Wired up but disabled by default,
    # see modules/security.nix before you enable it.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, sops-nix, lanzaboote, ... }@inputs:
    let
      system = "x86_64-linux";

      # Overlay giving every module access to `pkgs.unstable.<name>` for the
      # handful of fast-moving packages we do not want pinned to stable.
      overlay-unstable = final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
    in
    {
      nixosConfigurations.beta = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          { nixpkgs.overlays = [ overlay-unstable ]; }

          nixos-hardware.nixosModules.lenovo-thinkpad-t490s

          sops-nix.nixosModules.sops
          lanzaboote.nixosModules.lanzaboote

          ./hosts/t490s

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.coops = import ./home;
          }
        ];
      };

      # Convenience: `nix fmt` and a dev shell with the tools this repo needs.
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;

      devShells.${system}.default =
        let pkgs = nixpkgs.legacyPackages.${system};
        in pkgs.mkShell {
          packages = with pkgs; [ nixpkgs-fmt statix deadnix sops age ssh-to-age ];
        };
    };
}
