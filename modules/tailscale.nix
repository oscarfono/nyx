{ config, pkgs, lib, username, ... }:

# Tailscale, the client side. Import from hosts/t490/default.nix.
#
# This laptop joins the tailnet to reach the server. The tailnet is the only
# path to the server, because the server opens no public port.
#
# Do not install Tailscale with the install.sh script from tailscale.com.
# The script does not support NixOS. This module is the NixOS method.
#
# After the first switch, log in once:
#
#   tailscale up
#
# The command prints a URL. Open the URL and log in. The node key then stays
# in /var/lib/tailscale, so later boots connect with no login.
#
# The firewall stays closed, and tailscale0 is NOT a trusted interface here.
# The laptop starts connections to the server. The server does not start
# connections to the laptop. The Tailscale policy also blocks that
# direction, so a compromised server cannot reach this machine.
#
# UDP 41641 stays closed. Tailscale then uses NAT traversal, or a DERP relay
# when NAT traversal fails. A hotel network often blocks direct paths anyway.
#
# CAUTION: Proton VPN with the kill switch on can block the Tailscale
# traffic. If `tailscale status` shows the server as offline while Proton VPN
# is up, disconnect Proton VPN to find the cause.

{
  services.tailscale = {
    enable = true;

    # The operator can run `tailscale up`, `tailscale status` and
    # `tailscale set` without sudo.
    extraSetFlags = [ "--operator=${username}" ];
  };
}
