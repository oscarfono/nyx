# UNBUILT — 19 November 2026. Written in the agent's sandbox, which has no Nix,
# so this file has NEVER BEEN EVALUATED. Everything in it is either read from
# nixpkgs source or from disko's own examples on the day it was written; the
# list of what was verified and what was assumed is in hosts/vps/README.md.
#
# The command that settles it, from the machine with the flake on it:
#
#     nixos-rebuild build --flake ~/Projects/nyx#vps
#
# It evaluates and builds and does not switch, and it names any option it does
# not recognise. Run it before the box is worth anything.

{ config, pkgs, lib, inputs, username, fullName, email, ... }:

# The server. The machine that works, while the T490 keeps the keys.
#
# It is one entry in nixosConfigurations, which is what the flake was built
# for: "a desktop, a server or a second laptop is a new entry ... not a fork of
# this file."
{
  imports = [
    # disko turns ./disko.nix into filesystems and into
    # boot.initrd.luks.devices. Nothing about LUKS is hand-written here, which
    # is deliberate — one description, one place it can be wrong.
    inputs.disko.nixosModules.disko
    ./disko.nix
    ../../modules/server.nix
    ../../modules/security.nix      # sops, the firewall's posture, apparmor
  ];

  # =====================================================================
  # The disk layout is this file's sibling.
  # =====================================================================

  boot.loader = {
    systemd-boot.enable = lib.mkDefault true;
    systemd-boot.configurationLimit = 10;
    # On EFI hardware this is worth setting; on a guest whose firmware is
    # managed by the provider it may fail harmlessly. Recorded, not asserted:
    # if the install reports it could not touch EFI variables, set this to
    # false and rebuild.
    efi.canTouchEfiVariables = true;
    grub.enable = false;
    # NOT lanzaboote. Secure Boot on a rented guest belongs to the provider's
    # firmware — our own keys cannot be enrolled in someone else's boot chain,
    # and the flake imports lanzaboote's module for every host. It stays
    # disabled here, and its presence must not be read as protection.
  };

  # =====================================================================
  # REMOTE UNLOCK — the reason encryption is possible on a box with no
  # keyboard.
  #
  # With no key file, the passphrase is asked for in the initrd. There is no
  # screen, so the answer is to let him type it over SSH before the root
  # filesystem is open. The options below are verified against
  # nixos/modules/system/boot/initrd-ssh.nix in nixpkgs: enable, port, shell,
  # hostKeys, ignoreEmptyHostKeys, authorizedKeys, authorizedKeyFiles,
  # extraConfig.
  #
  # Two things to expect, so neither looks like a fault:
  #   1. `ssh -p 2222 root@<ip>` and type the passphrase. Nothing else happens
  #      until then — no ping, no port 22, no service.
  #   2. Host keys are generated per boot unless they are set explicitly, so
  #      the unlock host key changes every time. The resulting
  #      "REMOTE HOST IDENTIFICATION HAS CHANGED" warning is expected here and
  #      is NOT a sign of tampering. Do not "fix" it by trusting the key.
  # =====================================================================
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;              # not 22: it is the initrd, not the system
      authorizedKeys = [
        # REPLACE with the Director's own public key. This one line is the
        # whole of the unlock authentication, so an empty list here means a
        # machine that cannot be rebooted.
        "ssh-ed25519 AAAA... director@beta"
      ];
    };
  };

  # The system's own SSH is on 22 and is keys-only, set in modules/server.nix.

  # =====================================================================
  # The agent's sandbox expects /workspace to be ~/Projects.
  # =====================================================================
  # On the T490 this symlink lives in hosts/t490/default.nix, and
  # home/hermes.nix's docker_volumes assume it exists. Without it the agent
  # starts and finds no projects, which looks like a mount problem and is not.
  systemd.tmpfiles.rules = [
    "L+ /workspace - - - - ${config.home-manager.users.${username}.home.homeDirectory}/Projects"
  ];

  # =====================================================================
  # A server is not a desktop
  # =====================================================================
  system.stateVersion = "26.05";
  networking.hostName = "vps";

  # Nothing here yet holds the Matrix hub. That is the next module, and it is
  # written when the box answers — see hosts/vps/README.md for why it is not
  # in this file.
}
