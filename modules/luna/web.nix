{ config, lib, pkgs, hostName, site, ... }:
let
  luna-web = pkgs.callPackage ../../pkgs/luna-web { };
  fqdn = "${hostName}.${site.tailnet}";
  user = "luna_web";
  stateDir = "/var/lib/luna-web";

  # The secret key base and the release cookie stay on luna. The first start
  # makes them. To make new ones, delete the files and restart the service.
  start = pkgs.writeShellScript "luna-web-start" ''
    set -euo pipefail
    umask 077
    for name in secret_key_base cookie; do
      if [ ! -s "${stateDir}/$name" ]; then
        ${pkgs.openssl}/bin/openssl rand -hex 48 > "${stateDir}/$name"
      fi
    done
    RELEASE_COOKIE="$(cat ${stateDir}/cookie)"
    export RELEASE_COOKIE
    exec ${luna-web}/bin/luna_web start
  '';
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    # The unix socket only. No TCP port.
    settings.listen_addresses = lib.mkForce "";
    # Peer authentication only: the system user name is the role name.
    authentication = lib.mkForce ''
      local all all peer
    '';
    ensureDatabases = [ user ];
    ensureUsers = [ { name = user; ensureDBOwnership = true; } ];
  };

  users.groups.${user} = { };
  users.users.${user} = {
    isSystemUser = true;
    group = user;
    # The only client of the core API. Refer to "Build: the core API".
    extraGroups = [ "luna-api" ];
    home = stateDir;
  };
  # core.nix makes this group too. A test of this module alone needs it here.
  users.groups.luna-api = { };

  systemd.services.luna-web = {
    description = "LUNA web app (Phoenix)";
    # postgresql.target includes postgresql-setup, which makes the role.
    # The page works without the core, and shows a notice for each panel.
    after = [ "network.target" "postgresql.target" "luna-core.service" ];
    requires = [ "postgresql.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      LUNA_OWNER_LOGIN = site.ownerLogin;
      LUNA_WEB_ORIGIN = "https://${fqdn}:8443";
      LUNA_WEB_PORT = "8091";
      LUNA_WEB_SECRET_FILE = "${stateDir}/secret_key_base";
      LUNA_CORE_SOCKET = "/run/luna-api/api.sock";
      # The Wyoming servers in voice.nix. Without them, a voice turn shows a notice.
      LUNA_STT_URI = "tcp://127.0.0.1:10300";
      LUNA_TTS_URI = "tcp://127.0.0.1:10200";
      LUNA_DB_SOCKET_DIR = "/run/postgresql";
      LUNA_DB_USER = user;
      LUNA_DB_NAME = user;
      # No Erlang distribution: no epmd and no node port.
      RELEASE_DISTRIBUTION = "none";
      RELEASE_TMP = "/run/luna-web";
    };
    serviceConfig = {
      ExecStart = start;
      User = user;
      Group = user;
      StateDirectory = "luna-web";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "luna-web";
      RuntimeDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = 10;

      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectProc = "invisible";
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" "~@privileged" ];
    };
  };
}
