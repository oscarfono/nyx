{ config, pkgs, lib, ... }:

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
    terraform
    ansible
    kubectl
    kubernetes-helm
    k9s
    kubectx
    opentofu

    # Cloud
    awscli2
    azure-cli

    # Containers
    docker-compose
    dive
    trivy
    lazydocker

    # Secrets
    sops
    age
    ssh-to-age
    gnupg
    yubikey-manager
    pinentry-curses

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

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
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
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
