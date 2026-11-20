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

  services.openssh = {
    enable = true;
    openFirewall = site.bootstrap;
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
