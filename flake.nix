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
      inputs.rust-overlay.follows = "rust-overlay";
    };

    # The Rust toolchain that lanzaboote builds its boot tools with.
    #
    # lanzaboote v1.1.0 pins rust-overlay from June 2026. That revision
    # reads stdenv.isLinux and stdenv.isDarwin, and nixos-unstable marks
    # both as deprecated, so each evaluation printed two warnings. A newer
    # rust-overlay reads stdenv.hostPlatform instead.
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Caelestia, a Quickshell desktop shell. One process draws the bar, the
    # launcher, the notifications, the OSD and the panels.
    #
    # This input supplies the home-manager MODULE only. home-manager has no
    # module of its own for caelestia.
    #
    # CAUTION: do not use the package from this flake. The flake builds
    # quickshell from git with clang, and the binary cache holds no such
    # build, so the package compiles Qt and quickshell from source. That
    # build takes hours on this machine. home/caelestia.nix sets `package`
    # to the nixpkgs build, and the cache holds that build.
    caelestia = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hermes Agent, from Nous Research. This input supplies the
    # home-manager module and the package. See home/hermes.nix.
    #
    # The tag pins a stable release. The main branch gets a canary every
    # day.
    #
    # CAUTION: do not add `inputs.nixpkgs.follows`. The upstream docs do
    # not use it, and uv2nix builds the Python set against the nixpkgs of
    # the upstream lock.
    hermes-agent.url = "github:NousResearch/hermes-agent/v0.23.1";

    # Declarative disk layout, and the tool nixos-anywhere partitions with.
    #
    # A VPS has no hardware to probe, so that host has no
    # hardware-configuration.nix: hosts/luna/disko.nix IS that file.
    #
    # CAUTION: adding an input means flake.lock has no revision for it until
    # `nix flake update` runs once on a machine with Nix. Until then the
    # flake does not evaluate and the error names `disko`.
    disko = {
      url = "github:nix-community/disko/master";
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
        ./modules/craft.nix
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

          # LUNA, the personal assistant. A rented Vultr VPS.
          #
          # The design and the source of hosts/luna, modules/luna and
          # pkgs/luna-core are in luna/LUNA.org. Edit the org file, then
          # tangle. The install and deploy commands are in luna/Makefile.
          #
          # hardware = null, because a rented guest has no chassis to
          # profile. The server has no home-manager modules, but
          # home-manager needs a stateVersion.
          luna = mkHost {
            hostName = "luna";
            username = "coops";
            hardware = null;
            hostPath = ./hosts/luna;
            homeModules = [ { home.stateVersion = "26.05"; } ];
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

      # The LUNA packages. Each check runs the tests of its package.
      #   luna-core  the agent, in Python
      #   luna-web   the web app, in Phoenix. Its tests use a PostgreSQL
      #              server in the build directory.
      #   luna-core-ex  the core, in Elixir (stage E5). It replaces
      #              luna-core at the cutover.
      packages.${system} = {
        luna-core = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/luna-core { };
        luna-web = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/luna-web { };
        luna-core-ex = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/luna-core-ex { };
      };
      checks.${system} = {
        inherit (self.packages.${system}) luna-core luna-web luna-core-ex;
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;

      devShells.${system}.default =
        let pkgs = nixpkgs.legacyPackages.${system};
        in pkgs.mkShell {
          packages = with pkgs; [
            nixpkgs-fmt statix deadnix sops age ssh-to-age
            # LUNA install: luna/Makefile and luna/LUNA.org.
            nixos-anywhere mkpasswd openssl hledger
          ];
        };
    };
}
