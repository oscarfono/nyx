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

{ config, pkgs, lib, inputs, username, fullName, email, modulesPath, ... }:

# The server. The machine that works, while the T490 keeps the keys.
#
# It is one entry in nixosConfigurations, which is what the flake was built
# for: "a desktop, a server or a second laptop is a new entry ... not a fork of
# this file."
{
  imports = [
    # A rented KVM guest, and this line is not optional. It brings the virtio
    # disk and network drivers into the INITRD, turns on DHCP, and gives the
    # machine a clean ACPI shutdown path. Without it a hardened system can
    # install perfectly and then come up unable to find its own disk or its
    # network — because the installer's initrd carries drivers that the
    # installed system does not. Every published cloud recipe for NixOS on a
    # droplet or a cloud VM includes it, and its absence here was an omission
    # rather than a decision.
    #
    # It matters more, not less, as the providers change: Vultr, then DigitalOcean.
    # The profile is written for exactly this class of machine.
    "${modulesPath}/profiles/qemu-guest.nix"

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

  # =====================================================================
  # GRUB, NOT systemd-boot, AND DELIBERATELY SO
  # =====================================================================
  # This was written for systemd-boot on the assumption the instance boots
  # EFI. That assumption is not safe to ship: Vultr's own documentation for
  # custom images says the image "must match the server configuration, either
  # Legacy (BIOS) or UEFI", and at least one published Vultr + NixOS account
  # reports UEFI/GPT not working there at all. A wrong guess is not subtle —
  # the box does not come back and the fix is a console session and a
  # re-install.
  #
  # So the config stops guessing. GRUB with efiSupport installs BOTH houses:
  # its stage-1 goes into the MBR and the 1 MiB bios_grub partition (declared
  # in the sibling disko.nix) for a BIOS boot, and into the ESP for a UEFI
  # boot. One install, either firmware.
  #
  # canTouchEfiVariables is FALSE and efiInstallAsRemovable is TRUE, and they
  # belong together: this guest's NVRAM is the provider's, and a boot entry
  # written there may not persist or may not be writable at all. The removable
  # path writes EFI/BOOT/BOOTX64.EFI instead, which is the location firmware is
  # required to try first regardless of NVRAM — per NixOS's own option
  # documentation, it is what you turn on when you want a disk that boots
  # irrespective of the firmware's variable state.
  #
  # The one command that settles which mode this box is actually in, run on the
  # stock image before anything is installed:
  #
  #     ls /sys/firmware/efi
  #
  # A listing means EFI, "No such file or directory" means BIOS. Either answer
  # is now fine, which is the point — but it is worth knowing which one you got,
  # because it decides whether /boot is being read from the ESP.
  # Lanzaboote is enabled by modules/security.nix for every host; this is the
  # host that turns it off, with the reason written above.
  boot.lanzaboote.enable = lib.mkForce false;

  boot.loader = {
    efi.canTouchEfiVariables = false;
    grub = {
      enable = true;
      device = "/dev/vda";
      efiSupport = true;
      efiInstallAsRemovable = true;
      useOSProber = false;
    };
    systemd-boot.enable = lib.mkForce false;
  };

  # NOT lanzaboote, AND THIS IS THE LINE THE OLD COMMENT ONLY CLAIMED.
  #
  # security.nix enables lanzaboote unconditionally — it is the desktop's
  # Secure Boot story, and it is right there. Here it is wrong twice over:
  # Secure Boot on a rented guest belongs to the provider's firmware and our own
  # keys cannot be enrolled in someone else's boot chain; and lanzaboote is
  # incompatible with GRUB, which is what this host boots with, so leaving it
  # enabled fails the build on an assertion. The comment said "it stays disabled
  # here" for a whole day while nothing disabled it — the same defect as the
  # disko comment that said "by-id, not /dev/vda" above a line that said
  # /dev/vda. **A comment is not a setting.**

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
    # Required as well as the ssh block below: initrd-ssh.nix only activates at
    # all when (boot.initrd.network.enable || boot.initrd.systemd.network.enable)
    # is true, so the ssh options alone would be inert. Verified in the module at
    # the revision this flake pins.
    enable = true;
    ssh = {
      enable = true;
      port = 2222;              # not 22: it is the initrd, not the system

      # THE ONE LINE THAT MUST BE REPLACED BEFORE THIS BOX MATTERS.
      #
      # initrd-ssh.nix asserts that at least one key is present, and it does not
      # care whether the key is real — so a placeholder passes the build and then
      # fails to authenticate, which is the worst available combination: a green
      # build and a machine that cannot be unlocked. On an encrypted box whose
      # passphrase is only ever asked for in the initrd, that means no reboot
      # without the provider's web console.
      #
      # Replace it with the Director's own PUBLIC key (`cat ~/.ssh/id_ed25519.pub`
      # on beta). A public key is not a secret and is safe to hand over — but it
      # is his, so the desk will not invent one.
      authorizedKeys = [
        "ssh-ed25519 REPLACE-WITH-THE-DIRECTORS-PUBLIC-KEY director@beta"
      ];

      # And this is not optional either: the module asserts
      #   (hostKeys != []) || ignoreEmptyHostKeys
      # with the message "You must now pre-generate the host keys for initrd
      # SSH." The alternative is a private host key in the Nix store, which is
      # worse than a changing host key. So: accept empty host keys — a fresh one
      # each boot, and a "REMOTE HOST IDENTIFICATION HAS CHANGED" warning on every
      # unlock, which is expected here and NOT a sign of tampering.
      ignoreEmptyHostKeys = true;
    };
  };

  # ONE THING THIS FILE CANNOT PROMISE, and it is the unlock path.
  #
  # modules/security.nix sets boot.initrd.systemd.enable = true (it is there for
  # TPM2 unlock). Whether the scripted boot.initrd.network.enable above is fully
  # honoured under the systemd initrd, or whether
  # boot.initrd.systemd.network.enable is the one that matters, was NOT settled.
  # The module's condition accepts either and it wires the systemd side itself,
  # so the honest position is "expected to work, unverified" — recorded rather
  # than papered over with an extra option that could not be verified, because an
  # unverified defensive setting is not defensive. This file has learned that
  # twice already.
  #
  # The fallback is real and free: the provider's web console can type the
  # passphrase straight into the initrd prompt, which is what it is for.

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
