{
  description = "Nyx - an opinionated, security-first NixOS desktop";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # A prebuilt nix-index database, refreshed weekly upstream.
    #
    # programs.nix-index installs the command-not-found handler, but it does
    # not build the database. The `nix-index` command builds the database,
    # and that command reads all of nixpkgs. On a 16GB machine the command
    # exhausts the memory and the OOM killer stops it, so the database never
    # appears. Then every unknown command fails with an I/O error, and
    # `comma` cannot work at all.
    #
    # This input supplies the database as a store path instead. Run
    # `nix flake update` to get a newer one.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative secrets. Nothing plaintext in the repo.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secure Boot with your own keys. Wired up but disabled by default,
    # see modules/security.nix before you enable it.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-hardware, sops-nix, lanzaboote, nix-index-database, ... }@inputs:
    let
      system = "x86_64-linux";

      # mkHost is the whole multi-machine story.
      #
      # Everything machine-specific is an argument; everything else is a
      # shared module. A desktop, a server or a second laptop is a new entry
      # in nixosConfigurations below, not a fork of this file.
      #
      #   hostName   what the machine calls itself
      #   username   the human. Passed through to home-manager, so the repo
      #              is not welded to one account name.
      #   hardware   nixos-hardware module for this chassis, or null
      #   modules    which of ours this machine wants. A headless box would
      #              drop desktop.nix and fonts.nix and keep the rest.
      mkHost =
        { hostName
        , username
        , fullName ? "Cooper Oscarfono"
        , email ? "cooper@oscarfono.com"
        , hardware ? null
        , hostPath
        , modules ? [ ]
        , homeModules ? [ ./home ]
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs hostName username fullName email; };
          modules =
            (nixpkgs.lib.optional (hardware != null) hardware)
            ++ [
              sops-nix.nixosModules.sops
              lanzaboote.nixosModules.lanzaboote
              nix-index-database.nixosModules.nix-index
              hostPath
              { networking.hostName = hostName; }
            ]
            ++ modules
            ++ [
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                # Move pre-existing files aside instead of aborting
                # activation. Without this, one stray file (a default
                # hyprland.lua, say) blocks the entire user config.
                home-manager.backupFileExtension = "hm-bak";
                home-manager.extraSpecialArgs = {
                  inherit inputs hostName username fullName email;
                };
                home-manager.users.${username}.imports = homeModules;
              }
            ];
        };

      # The full desktop module set. A different class of machine picks a
      # different list.
      desktopModules = [
        ./modules/apps.nix
        ./modules/desktop.nix
        ./modules/devops.nix
        ./modules/emacs.nix
        ./modules/fonts.nix
        ./modules/languages.nix
        ./modules/power.nix
        ./modules/secrets.nix
        ./modules/security.nix
      ];
    in
      {
        nixosConfigurations = {
          beta = mkHost {
            hostName = "beta";
            username = "coops";
            hardware = nixos-hardware.nixosModules.lenovo-thinkpad-t490;
            hostPath = ./hosts/t490;
            modules = desktopModules;
          };

          # Adding a machine looks like this. Copy hosts/t490 to hosts/<name>,
          # regenerate hardware-configuration.nix on that machine, and drop or
          # add modules to taste.
          #
          # gamma = mkHost {
          #   hostName = "gamma";
          #   username = "sod";
          #   hardware = null;                       # desktop, no profile
          #   hostPath = ./hosts/desktop;
          #   modules = desktopModules ++ [ ./modules/gaming.nix ];
          # };
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;

      devShells.${system}.default =
        let pkgs = nixpkgs.legacyPackages.${system};
        in pkgs.mkShell {
          packages = with pkgs; [ nixpkgs-fmt statix deadnix sops age ssh-to-age ];
        };
    };
}
