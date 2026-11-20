{ config, pkgs, hostName, site, ... }:
let
  fqdn = "${hostName}.${site.tailnet}";
  synapse = config.services.matrix-synapse.package;
  secretsConfig = config.sops.templates."synapse-secrets.yaml".path;
in
{
  services.matrix-synapse = {
    enable = true;
    settings = {
      server_name = fqdn;
      public_baseurl = "https://${fqdn}/";
      listeners = [
        {
          port = 8008;
          bind_addresses = [ "127.0.0.1" ];
          type = "http";
          tls = false;
          x_forwarded = true;
          resources = [ { names = [ "client" ]; compress = true; } ];
        }
      ];
      database.name = "sqlite3";
      # Room version 12 (MSC4291) makes room IDs with no server part.
      # ement.el refuses such a room ID. Room version 11 works with all
      # clients.
      default_room_version = "11";
      enable_registration = false;
      federation_domain_whitelist = [ ];
      allow_public_rooms_over_federation = false;
      trusted_key_servers = [ ];
      suppress_key_server_warning = true;
      url_preview_enabled = false;
      presence.enabled = false;
      report_stats = false;
    };
    extraConfigFiles = [ secretsConfig ];
  };

  sops.secrets.matrix-registration-secret = { };
  sops.templates."synapse-secrets.yaml" = {
    owner = "matrix-synapse";
    content = ''
      registration_shared_secret: "${config.sops.placeholder.matrix-registration-secret}"
    '';
  };

  systemd.services.luna-tailscale-serve = {
    description = "Publish the Matrix homeserver on the tailnet with HTTPS";
    after = [ "tailscaled.service" "matrix-synapse.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 15;
    };
    script = ''
      ${config.services.tailscale.package}/bin/tailscale serve --bg --https=443 http://127.0.0.1:8008
      # The Phoenix app. Refer to "Build: the Phoenix app".
      ${config.services.tailscale.package}/bin/tailscale serve --bg --https=8443 http://127.0.0.1:8091
      # Stage E1 used port 8444 for the Python app. Delete that serve rule.
      ${config.services.tailscale.package}/bin/tailscale serve --https=8444 off || true
    '';
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "luna-register-user" ''
      exec ${synapse}/bin/register_new_matrix_user -c ${secretsConfig} "$@" http://127.0.0.1:8008
    '')
  ];
}
