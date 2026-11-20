{ lib, pkgs, modulesPath, inputs, ... }:
let
  site = import ./site.nix;
  secretsFile = ../../secrets/luna.yaml;
  secretsReady = builtins.pathExists secretsFile;
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
    ./disko.nix
    ../../modules/luna/hardening.nix
    ../../modules/luna/access.nix
    ../../modules/luna/matrix.nix
    ../../modules/luna/core.nix
    ../../modules/luna/web.nix
  ];

  _module.args = { inherit site secretsReady; };

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  boot.initrd.availableKernelModules = [
    "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "virtio_blk" "sd_mod" "sr_mod"
  ];

  networking.useDHCP = true;
  time.timeZone = site.timeZone;
  zramSwap.enable = true;

  # Without the secrets file, the configuration evaluates for checks only.
  # The install target refuses to start without the secrets file.
  sops = {
    defaultSopsFile =
      if secretsReady then secretsFile else "/run/luna-no-secrets.yaml";
    validateSopsFiles = secretsReady;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
  warnings = lib.optional (!secretsReady)
    "secrets/luna.yaml does not exist. Run 'make secrets' before 'make install'.";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    allowed-users = [ "@wheel" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  environment.systemPackages = with pkgs; [ git hledger htop ripgrep ];

  system.stateVersion = "26.05";
}
