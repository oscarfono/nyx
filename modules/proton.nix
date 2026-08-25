{ config, pkgs, lib, ... }:

# The Proton suite.
#
# Five applications, one account, one vendor. Proton replaces the VPN, the
# password manager, the TOTP store, and the mail client in one move. That is
# convenient and it is also a single point of failure, so read the keyring
# note below before you trust it with anything.
#
# The session-level parts live in home/proton.nix: the Secret Service that
# these applications store their credentials in, and the Bridge user
# service. Neither belongs at the system layer, because both follow the
# graphical session.
#
# NOT INSTALLED, deliberately:
#
#   Proton Drive   Proton ships no Linux client. The web application is the
#                  only supported route. `rclone` speaks the Drive protocol
#                  through its `protondrive` backend if you want a mount.
#
#   proton-authenticator-bin
#                  The pre-built binary carries a non-free licence.
#                  proton-authenticator below builds the same 1.1.6 from
#                  source under a free licence, so the unfree list in
#                  modules/apps.nix does not have to grow.

{
  environment.systemPackages = with pkgs; [
    # -----------------------------------------------------------------
    # VPN
    # -----------------------------------------------------------------
    # The GTK client drives NetworkManager. modules/desktop.nix already
    # installs the networkmanager-openvpn plugin, and WireGuard is in the
    # kernel, so both transports work with no extra plugin here.
    proton-vpn
    proton-vpn-cli        # same account, no GTK, for scripts and TTY use

    # -----------------------------------------------------------------
    # Credentials
    # -----------------------------------------------------------------
    # WARNING: this overlaps KeePassXC, which modules/apps.nix installs and
    # which stays the local, offline vault. Proton Pass syncs through
    # Proton's servers. Decide which secret goes where BEFORE you import
    # anything, because a copy in both places is a copy you will forget to
    # rotate in one of them.
    proton-pass
    proton-pass-cli

    # TOTP codes, with optional sync. Sync is off until you turn it on.
    # Keep the second factor and the password in different vaults, or the
    # second factor stops being a second factor.
    proton-authenticator

    # -----------------------------------------------------------------
    # Mail
    # -----------------------------------------------------------------
    # Electron, and it duplicates the `proton` web application entry in
    # lib/webapps.nix. Both can co-exist. Delete the lib/webapps.nix entry
    # and the workspace 3 rule in home/desktop.nix once you decide which
    # one you keep.
    protonmail-desktop
  ];

  # ---------------------------------------------------------------------
  # DNS, and why a VPN changes the picture
  # ---------------------------------------------------------------------
  # WARNING: read this before you rely on the VPN for privacy.
  #
  # modules/security.nix sets `Domains = "~."` on the global resolved
  # configuration to force every lookup to Quad9. That is the right default
  # with no VPN, because it takes the ISP resolver out of the path.
  #
  # It fights the VPN. When Proton VPN connects, NetworkManager gives
  # resolved a per-link DNS server on the tunnel and claims `~.` for that
  # link too. Two links then both claim the route-all domain. resolved asks
  # both and uses the first reply, so a name you look up inside the tunnel
  # can be resolved by Quad9 outside it. The traffic still goes through the
  # tunnel. The query about where it goes does not.
  #
  # This module does not change that setting, because the current value is
  # correct while the VPN is down, and that is most of the time. Make the
  # choice yourself once you know how you use the VPN:
  #
  #   1. Connect the VPN.
  #   2. Run `resolvectl status` and read the Domains on each link.
  #   3. Run `resolvectl query <name>` and read which link answered.
  #
  # To hand DNS to the tunnel while it is up, drop `Domains = "~."` from
  # services.resolved in modules/security.nix. Quad9 stays the configured
  # server for the physical links. Nothing else in that block changes.

  # ---------------------------------------------------------------------
  # Keyring
  # ---------------------------------------------------------------------
  # Every application above stores its session through the Secret Service
  # D-Bus interface. proton-vpn depends on proton-keyring-linux for it, and
  # the three Electron applications use the same interface.
  #
  # This machine has no gnome-keyring, and it does not get one. KeePassXC
  # serves org.freedesktop.secrets from the kdbx you already control, so
  # there is no second credential store and no new daemon.
  #
  # KeePassXC ships no D-Bus activation file. It claims the bus name only
  # while it runs, which is why home/proton.nix starts it as a session
  # service. Nothing is needed at the system layer.
}
