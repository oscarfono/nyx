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

{ config, pkgs, lib, username, ... }:

# The headless baseline — what a machine nobody sits in front of needs, and
# nothing that a desktop needs.
#
# It is deliberately small. A server's attack surface is the set of things it
# runs, so this file is the list of things one of ours is allowed to be. If a
# package or a daemon is not named here or by a module this file imports, it is
# not on the machine.
#
# The exposure rules it implements are policy 09's (the vault's
# policies/09-encryption-and-exposure.org): no service reachable on an inbound
# port, TLS from a real authority, and every exposure written down.
{
  # ---------------------------------------------------------------------
  # Administration. THE ONE NAMED EXCEPTION TO "NO INBOUND PORTS".
  # ---------------------------------------------------------------------
  # A rented machine has no keyboard, so SSH is the only way in and it cannot
  # be behind the tunnel it is used to build. Policy 09 rule 6 says no service
  # is reachable on an inbound port; this is the exception, it is deliberate,
  # and it is recorded in that policy's register as an exposure rather than
  # left as an oversight.
  #
  # Keys only. No password path at all, and root cannot log in with one.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
      MaxAuthTries = 3;
      # Nobody logs in as a human on this box; the Director's key does the
      # only interactive work and everything else is a service account.
      X11Forwarding = false;
      AllowAgentForwarding = false;
    };
  };

  # A password on a service account is a password that gets reused. No user on
  # this machine has one.
  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    # The key is set by the host file, because it is per-person, not
    # per-machine-class.
  };
  security.sudo.wheelNeedsPassword = false;   # the key IS the factor

  # ---------------------------------------------------------------------
  # The network. Nothing is listening that we did not put there.
  # ---------------------------------------------------------------------
  networking = {
    useDHCP = lib.mkDefault true;         # rented boxes are handed an address
    firewall = {
      enable = true;
      # Deliberately empty. Anything that needs a port opens it in the module
      # that owns the service, next to the reason, so the list of holes is the
      # set of files that mention `openFirewall`.
      allowedTCPPorts = [ ];
      allowedUDPPorts = [ ];
    };
    # Rented hardware does not get to be a router or a discovery node.
    networkmanager.enable = false;
  };

  # ---------------------------------------------------------------------
  # An attacker gets a small number of tries, then the door shuts for a while
  # ---------------------------------------------------------------------
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    jails.sshd.settings = {
      enabled = true;
      mode = "aggressive";
    };
  };

  # ---------------------------------------------------------------------
  # Machine hygiene
  # ---------------------------------------------------------------------
  time.timeZone = "Asia/Singapore";       # the box's own clock; him, not it
  i18n.defaultLocale = "en_AU.UTF-8";

  # The nix store grows forever on a machine that is rebuilt from a
  # description. Collect weekly and keep two weeks of generations.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings.auto-optimise-store = true;

  # A small disk fills with journals before anything else does.
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=1month
  '';

  # ---------------------------------------------------------------------
  # Rented hardware niceties
  # ---------------------------------------------------------------------
  # Vultr's KVM guests speak virtio and appreciate being told to shut down
  # politely rather than being powered off.
  services.qemuGuest.enable = true;
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" "ahci" "sd_mod" "usbhid" "usb_storage" ];
  boot.kernelModules = [ ];

  # No sound, no bluetooth, no power management — a server has no body.
  services.xserver.enable = false;
  sound.enable = false;
  hardware.enableRedistributableFirmware = false;

  # ---------------------------------------------------------------------
  # Time, so TLS and Matrix both work
  # ---------------------------------------------------------------------
  services.timesyncd.enable = true;

  # ---------------------------------------------------------------------
  # The one thing a machine like this must not be
  # ---------------------------------------------------------------------
  # Nothing here enables federation, registration, or a public listener. If a
  # future module needs one, it opens it where the reason lives, and policy 09
  # rule 9 requires the exposure to appear in that policy's register the same
  # day. An exposure that is not on the list is unaudited.
}
