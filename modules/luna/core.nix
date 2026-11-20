{ config, lib, pkgs, hostName, username, site, ... }:
let
  luna-core = pkgs.callPackage ../../pkgs/luna-core { };
  fqdn = "${hostName}.${site.tailnet}";
  stateDir = "/var/lib/luna";
  secret = name: config.sops.secrets.${name}.path;
  credentials =
    [
      "anthropic_api_key:${secret "anthropic-api-key"}"
      "matrix_password:${secret "luna-matrix-password"}"
    ]
    ++ lib.optionals site.telegram [
      "telegram_token:${secret "telegram-bot-token"}"
      "telegram_chat_id:${secret "telegram-chat-id"}"
    ];

  memoryInit = pkgs.writeShellScript "luna-memory-init" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.git pkgs.coreutils ]}
    export GIT_AUTHOR_NAME=LUNA GIT_AUTHOR_EMAIL=luna@${fqdn}
    export GIT_COMMITTER_NAME=LUNA GIT_COMMITTER_EMAIL=luna@${fqdn}
    hub=${stateDir}/memory.git
    work=${stateDir}/memory
    if [ ! -d "$hub" ]; then
      git init --bare --shared=group --initial-branch=main "$hub"
    fi
    if [ ! -d "$work/.git" ]; then
      git clone "$hub" "$work"
      if [ -z "$(git -C "$work" rev-parse --verify --quiet HEAD || true)" ]; then
        cp -r --no-preserve=mode ${../../luna/memory-seed}/. "$work/"
        git -C "$work" add -A
        git -C "$work" commit -m "Add the memory seed files"
        git -C "$work" branch -M main
        git -C "$work" push --set-upstream origin main
      fi
    fi
  '';
in
{
  users.groups.luna = { };
  users.users.luna = {
    isSystemUser = true;
    group = "luna";
    home = stateDir;
  };

  sops.secrets = {
    anthropic-api-key = { };
    luna-matrix-password = { };
  } // lib.optionalAttrs site.telegram {
    telegram-bot-token = { };
    telegram-chat-id = { };
  };

  # Let the owner use the hub that the user "luna" owns.
  programs.git = {
    enable = true;
    config.safe.directory = [ "${stateDir}/memory.git" ];
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 2750 luna luna -"
    "d ${stateDir}/approvals 0700 luna luna -"
    "d ${stateDir}/audit 0750 luna luna -"
    "f ${stateDir}/audit/audit.jsonl 0640 luna luna -"
    "h ${stateDir}/audit/audit.jsonl - - - - +a"
  ];

  systemd.services.luna-core = {
    description = "LUNA core agent";
    after = [ "network-online.target" "matrix-synapse.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.git ];
    environment = {
      LUNA_STATE_DIR = stateDir;
      LUNA_HOMESERVER = "http://127.0.0.1:8008";
      LUNA_MATRIX_USER = "@luna:${fqdn}";
      LUNA_OWNER = "@${username}:${fqdn}";
      LUNA_OWNER_TIMEZONE = site.ownerTimeZone;
      LUNA_BRIEF_TIME = site.briefTime;
      LUNA_MODEL = "claude-opus-5-5";
      LUNA_EFFORT = "medium";
      GIT_AUTHOR_NAME = "LUNA";
      GIT_AUTHOR_EMAIL = "luna@${fqdn}";
      GIT_COMMITTER_NAME = "LUNA";
      GIT_COMMITTER_EMAIL = "luna@${fqdn}";
    };
    serviceConfig = {
      ExecStartPre = memoryInit;
      ExecStart = "${luna-core}/bin/luna-core";
      User = "luna";
      Group = "luna";
      UMask = "0007";
      LoadCredential = credentials;
      Restart = "on-failure";
      RestartSec = 30;

      ReadWritePaths = [ stateDir ];
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
