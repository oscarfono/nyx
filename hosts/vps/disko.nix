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

# The disk, declared rather than discovered.
#
# A VPS has no hardware to probe, so there is no hardware-configuration.nix
# here: this file IS that file. nixos-anywhere hands it to disko, disko
# partitions and formats, and the encryption below is what makes the machine
# safe to hold the company's keys.
#
# =====================================================================
# THE ONE THING TO CHECK BEFORE INSTALLING
# =====================================================================
# Whether the instance boots BIOS or EFI. This file is written for EFI, which
# is what a current Vultr KVM instance is. On the running Debian image:
#
#     ls /sys/firmware/efi
#
# A directory listing means EFI and this file is correct. "No such file or
# directory" means legacy BIOS: then the ESP partition below becomes a
# 1 MiB grub-bios partition, /boot moves onto the root filesystem, and the
# host file uses grub rather than systemd-boot. Getting this wrong is not
# subtle — the box does not come back after the install, and the fix is a
# console session and a re-install.
{
  disko.devices = {
    disk.main = {
      type = "disk";
      # /dev/vda is the first virtio disk, and on this instance it is the only
      # one. The comment here used to say "by-id, not /dev/vda" while the line
      # below it said /dev/vda — a rule and its opposite in four lines, which is
      # the third time this project has written one. On a rented guest there is
      # no stable by-id path to write, because the disk is the provider's, so
      # /dev/vda is correct HERE and the safety measure is the command rather
      # than the path: `lsblk` on the running image, before the install, and the
      # answer must name exactly one disk. numtide's own Vultr walkthrough uses
      # /dev/vda for the same reason.
      device = "/dev/vda";
      content = {
        type = "gpt";
        partitions = {
          # A 1 MiB unformatted partition with no filesystem, which is where
          # GRUB embeds its core image when the machine boots BIOS rather than
          # UEFI. It is here because the firmware mode of a rented instance is
          # NOT known in advance and getting it wrong is the failure this file
          # already warned about: the box does not come back after the install.
          #
          # Confirmed against disko's own example/hybrid.nix, which is exactly
          # this layout — a partition with a size and a type and NOTHING else is
          # valid, and the 1M EF02 partition is its documented purpose ("for
          # grub MBR"). The alternative was to guess the mode and ship a config
          # that only survives a correct guess.
          boot = {
            size = "1M";
            type = "EF02";
          };
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              # NO keyFile AND NO passwordFile.
              #
              # That is the point: the passphrase is prompted for in the
              # initrd, which is what makes this encryption rather than
              # decoration. A key file on the machine would sit next to the
              # lock; a key file loaded into the Nix store would be readable
              # from the store.
              #
              # nixos-anywhere needs to OPEN this volume to install into it,
              # so the installer supplies the passphrase for the duration of
              # the install. That is what its disk-encryption-keys flag is for
              # — the exact flag name is confirmed in the runbook, on the
              # machine that runs it, with `--help`.
              settings.allowDiscards = true;
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
