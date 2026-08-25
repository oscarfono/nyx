{ config, pkgs, lib, ... }:

# Session half of the Proton suite. The applications themselves are in
# modules/proton.nix; read the warnings there first.
#
# Two things live here because both follow the graphical session:
#
#   1. KeePassXC, running as the Secret Service that every Proton
#      application stores its login session in.
#   2. Proton Mail Bridge, which turns the account into local IMAP and SMTP.

{
  # ---------------------------------------------------------------------
  # Secret Service
  # ---------------------------------------------------------------------
  # Proton stores its sessions through the org.freedesktop.secrets D-Bus
  # interface. KeePassXC provides that interface from the kdbx you already
  # own, so this machine keeps one credential store instead of two.
  #
  # KeePassXC ships no D-Bus activation file. It claims the bus name only
  # while the process runs. Nothing can start it on demand, so it has to be
  # a session service.
  #
  # MANUAL STEP, once. The integration is off by default and KeePassXC keeps
  # the setting in its own configuration, not in Nix:
  #
  #   1. Open KeePassXC.
  #   2. Go to Tools > Settings > Secret Service Integration.
  #   3. Select "Enable KeePassXC Freedesktop.org Secret Service
  #      integration".
  #   4. Open Database > Database Settings > Secret Service Integration.
  #   5. Select the group that you want to expose. Make a group named
  #      "Proton" and expose only that group.
  #   6. Restart the service: `systemctl --user restart keepassxc`.
  #
  # Step 5 matters. Exposing the whole database gives every application in
  # your session read access to every entry in it over D-Bus.
  #
  # CONSEQUENCE: the database must be unlocked before a Proton application
  # can save or read its session. A locked kdbx means Proton VPN asks you to
  # sign in again. That is the trade you took by not running gnome-keyring,
  # and it is the reason the Bridge service below retries slowly.
  systemd.user.services.keepassxc = {
    Unit = {
      Description = "KeePassXC (Secret Service provider)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      # --minimized puts it in the waybar tray instead of opening a window
      # at every login. home/desktop.nix enables the tray module.
      ExecStart = "${pkgs.keepassxc}/bin/keepassxc --minimized";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # ---------------------------------------------------------------------
  # Proton Mail Bridge
  # ---------------------------------------------------------------------
  # Proton encrypts mail, so no standard client can talk to the account
  # directly. Bridge signs in, decrypts locally, and serves the result on
  # the loopback interface:
  #
  #   IMAP  127.0.0.1:1143
  #   SMTP  127.0.0.1:1025
  #
  # Bridge generates its own password per client. Read it from the Bridge
  # window, not from your Proton password. Both ports are loopback only, so
  # the firewall in modules/security.nix needs no change.
  #
  # Nothing on this machine consumes these ports yet. There is no mu4e, no
  # notmuch, and no mbsync in home/emacs.nix. The service runs so that the
  # account is ready when you wire up a client.
  #
  # FIRST RUN: the service starts with --noninteractive, which cannot ask
  # you to sign in. Sign in once from a terminal, then let the service take
  # over:
  #
  #   systemctl --user stop protonmail-bridge
  #   protonmail-bridge --cli      # then: login
  #   systemctl --user start protonmail-bridge
  services.protonmail-bridge = {
    enable = true;
    logLevel = "warn";
  };

  # Two corrections to the home-manager unit.
  #
  # Bridge needs the Secret Service to read its stored credentials, and
  # KeePassXC only provides that interface after you unlock the database.
  # The home-manager module sets Restart = "always" with no delay, so on a
  # locked database Bridge restarts about ten times a second and fills the
  # journal until you unlock it.
  #
  # RestartSec makes the retry cost nothing. The ordering below starts
  # Bridge after KeePassXC, which removes the race at login but does not
  # help with the unlock, because systemd cannot know when you type the
  # passphrase. The retry handles that part.
  systemd.user.services.protonmail-bridge = {
    Unit.After = [ "keepassxc.service" ];
    Service.RestartSec = 30;
  };
}
