{ config, hostName, username, site, ... }:
let
  password = config.sops.secrets."${username}-password".path;
in
{
  users.mutableUsers = false;

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "luna" ];
    openssh.authorizedKeys.keys = site.sshKeys;
    hashedPasswordFile = password;
  };
  users.users.root = {
    openssh.authorizedKeys.keys = site.sshKeys;
    hashedPasswordFile = password;
  };

  sops.secrets."${username}-password".neededForUsers = true;
  sops.secrets.tailscale-authkey = { };

  security.sudo.wheelNeedsPassword = true;

  # sshd runs during the bootstrap only. After the bootstrap, tailscaled
  # serves all SSH on the tailnet (Tailscale SSH). The Vultr console is the
  # way in when Tailscale fails.
  services.openssh = {
    enable = site.bootstrap;
    openFirewall = site.bootstrap;
    # The ed25519 key from `make host-key` is the only host key. Without this
    # line, NixOS also makes an RSA key, and sops-nix tries to read it as a
    # GPG key.
    hostKeys = [ { path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; } ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.tailscale-authkey.path;
    extraUpFlags = [ "--ssh" "--hostname=${hostName}" ];
  };

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };
}
