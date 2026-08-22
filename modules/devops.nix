{ config, pkgs, lib, inputs, username, ... }:

# The part that earns the "devops/secops dream setup" description.

{
  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  virtualisation.libvirtd = {
    enable = true;
    qemu.swtpm.enable = true;
    # qemu.ovmf was removed upstream: all OVMF images shipped with QEMU are
    # now available by default. Nothing to declare.
  };
  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [
    # Version control and CI
    git
    git-crypt
    gh
    lazygit
    pre-commit

    # Infra
    # No terraform: BSL 1.1 since HashiCorp's relicence. opentofu is the
    # MPL-licenced fork and a drop-in replacement, so `tofu` is the command.
    # If a workplace ever mandates terraform proper, add it here and to the
    # allowUnfreePredicate list in apps.nix.
    ansible
    kubectl
    kubernetes-helm
    k9s
    kubectx
    opentofu

    # Cloud
    awscli2
    azure-cli

    # Payments. `stripe listen` forwards webhooks to a local port, which is
    # the only way to test a webhook handler without a public URL.
    stripe-cli

    # Containers
    docker-compose
    dive
    trivy
    lazydocker

    # Secrets
    sops
    age
    mkpasswd
    ssh-to-age
    gnupg
    yubikey-manager
    pinentry-gnome3

    # Hardware inspection. Not installed by default on NixOS, which is why
    # lsusb/lspci come back as command-not-found on a fresh system.
    usbutils
    pciutils
    dmidecode

    # Network and inspection
    nmap
    tcpdump
    wireshark
    mtr
    doggo
    bandwhich
    termshark

    # Security scanning
    lynis
    clamav
    gitleaks
    # rkhunter is not packaged in nixpkgs, and it would be near-useless here
    # anyway: it checks for modified system binaries, and on NixOS the store
    # is read-only and every path is hash-verified. vulnix is the Nix-native
    # equivalent and actually tells you something useful: it audits the store
    # against known CVEs.
    vulnix

    # Shell quality of life
    nvd          # nix version diff, used by nh
    # No plain `comma` here. programs.nix-index-database.comma.enable below
    # installs a comma that knows where the database is. Two comma packages
    # in systemPackages collide.

    ripgrep
    fd
    bat
    eza
    fzf
    jq
    yq-go
    tmux
    zellij
    direnv
    just
    htop
    btop
    ncdu
  ];

  # nh wraps nixos-rebuild with a progress view and, more usefully, prints a
  # diff of what actually changed between generations. NH_FLAKE means
  # `nh os switch` needs no path argument.
  programs.nh = {
    enable = true;
    flake = "/home/${username}/Projects/nyx";
    clean = {
      enable = true;
      extraArgs = "--keep 5 --keep-since 14d";
    };
  };

  # nh clean removes generations from the store, but the UKIs on the ESP are
  # only pruned when lanzaboote next installs. Without this, /boot keeps
  # images for generations that no longer exist — and with a specialisation
  # each, that adds up fast on a 1GB partition.
  systemd.services.nh-clean.serviceConfig.ExecStartPost =
    "/run/current-system/bin/switch-to-configuration boot";

  # comma: run a program you do not have, once, without installing it.
  #   , cowsay hello
  #
  # comma and the command-not-found handler both read the nix-index
  # database. programs.nix-index does NOT build that database. The
  # `nix-index` command builds it, and that command reads all of nixpkgs:
  # on a 16GB machine it exhausts the memory and the OOM killer stops it.
  #
  # The nix-index-database flake input supplies a prebuilt database, and
  # its module points nix-index and comma at that database. See the
  # nix-index section in CHEATSHEET.md.
  programs.command-not-found.enable = false;   # replaced by nix-index
  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.nix-index-database.comma.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # gpg-agent runs as a home-manager user service (home/agents.nix), not
  # here. Two agents fighting over ~/.gnupg sockets is a bad afternoon.
  # This stays off deliberately.
  programs.gnupg.agent = {
    enable = false;
    enableSSHSupport = false;
    # NOT pinentry-curses. The Emacs daemon has no terminal, so a curses
    # prompt has nowhere to draw and the passphrase request hangs forever,
    # which looks exactly like the daemon failing to start.
    pinentryPackage = pkgs.pinentry-gnome3;
  };

  # YubiKey / smartcard support, since GPG and FIDO2 both want it.
  services.pcscd.enable = true;
  hardware.gpgSmartcards.enable = true;

  # Nix itself
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "root" "@wheel" ];
  };
  # Pin `nix shell nixpkgs#foo`, `nix repl '<nixpkgs>'` and friends to the
  # exact nixpkgs this system was built from. Without this, ad-hoc commands
  # silently use a different, unpinned nixpkgs than the system, which is the
  # sort of drift this whole project exists to avoid.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  # Garbage collection is handled by programs.nh.clean above. Enabling
  # nix.gc.automatic as well makes them fight over the same generations, and
  # NixOS warns about it.
  # nix.gc = {
  #   automatic = true;
  #   dates = "weekly";
  #   options = "--delete-older-than 30d";
  # };
}
