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
    ++ lib.optionals (lib.elem site.wise.mode [ "draft" "auto" ]) [
      "wise_api_token:${secret "wise-api-token"}"
    ]
    ++ lib.optionals site.telegram [
      "telegram_token:${secret "telegram-bot-token"}"
      "telegram_chat_id:${secret "telegram-chat-id"}"
    ];

  # The hub refuses raw bank exports. Raw exports go to the inbox, not to git.
  preReceive = pkgs.writeShellScript "luna-memory-pre-receive" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.git pkgs.coreutils pkgs.gnugrep ]}
    zero=0000000000000000000000000000000000000000
    status=0
    while read -r old new ref; do
      [ "$new" = "$zero" ] && continue
      if [ "$old" = "$zero" ]; then range="$new --not --all"; else range="$old..$new"; fi
      # shellcheck disable=SC2086
      bad=$(git log --name-only --diff-filter=AM --format= $range \
        | grep -iE '\.(csv|ofx|qif|qfx|xls|xlsx|pdf)$' || true)
      if [ -n "$bad" ]; then
        echo "LUNA: the memory refuses raw bank exports and statements:" >&2
        echo "$bad" | sed 's/^/  /' >&2
        echo "LUNA: send exports with 'make money-upload FILES=...'." >&2
        status=1
      fi
    done
    exit $status
  '';

  memoryInit = pkgs.writeShellScript "luna-memory-init" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.git pkgs.coreutils pkgs.findutils ]}
    export GIT_AUTHOR_NAME=LUNA GIT_AUTHOR_EMAIL=luna@${fqdn}
    export GIT_COMMITTER_NAME=LUNA GIT_COMMITTER_EMAIL=luna@${fqdn}
    hub=${stateDir}/memory.git
    work=${stateDir}/memory
    seed=${../../luna/memory-seed}
    if [ ! -d "$hub" ]; then
      git init --bare --shared=group --initial-branch=main "$hub"
    fi
    # Install the hook at each start, so the hook follows the configuration.
    cat ${preReceive} > "$hub/hooks/pre-receive"
    chmod 0775 "$hub/hooks/pre-receive"
    if [ ! -d "$work/.git" ]; then
      git clone "$hub" "$work"
    fi
    # The working copy has no commit. This is the first start, or a first
    # start that stopped before the commit.
    if ! git -C "$work" rev-parse --verify --quiet HEAD >/dev/null; then
      git -C "$work" symbolic-ref HEAD refs/heads/main
      if git -C "$hub" rev-parse --verify --quiet refs/heads/main >/dev/null; then
        # The hub has commits, for example from the laptop. Use them.
        git -C "$work" fetch origin
        git -C "$work" reset --hard origin/main
      else
        # Copy the seed without cp. cp sets the mode of each directory,
        # and RestrictSUIDSGID refuses a mode with the setgid bit. mkdir
        # and a redirect let the kernel set the inherited bits.
        (cd "$seed" && find . -type d) | while read -r d; do mkdir -p "$work/$d"; done
        (cd "$seed" && find . -type f) | while read -r f; do cat "$seed/$f" > "$work/$f"; done
        git -C "$work" add -A
        git -C "$work" commit -m "Add the memory seed files"
      fi
      git -C "$work" push --set-upstream origin main
    fi
    # Add seed files that a later version of LUNA brought. Never overwrite a
    # file: the memory belongs to the owner after the first start.
    if git -C "$work" pull --ff-only --quiet; then
      (cd "$seed" && find . -type f) | while read -r f; do
        if [ ! -e "$work/$f" ]; then
          mkdir -p "$work/$(dirname "$f")"
          cat "$seed/$f" > "$work/$f"
          git -C "$work" add -- "$f"
        fi
      done
      if ! git -C "$work" diff --cached --quiet; then
        git -C "$work" commit --quiet -m "Add new memory seed files"
        git -C "$work" push --quiet origin main
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
  } // lib.optionalAttrs (lib.elem site.wise.mode [ "draft" "auto" ]) {
    wise-api-token = { };
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
    # The upload inbox for raw bank exports. The owner can write, luna reads.
    # The import deletes each file after the import.
    "d ${stateDir}/inbox 2770 luna luna -"
    "d ${stateDir}/audit 0750 luna luna -"
    "f ${stateDir}/audit/audit.jsonl 0640 luna luna -"
    "h ${stateDir}/audit/audit.jsonl - - - - +a"
  ];

  systemd.services.luna-core = {
    description = "LUNA core agent";
    after = [ "network-online.target" "matrix-synapse.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.git pkgs.hledger ];
    environment = {
      LUNA_STATE_DIR = stateDir;
      LUNA_HOMESERVER = "http://127.0.0.1:8008";
      LUNA_MATRIX_USER = "@luna:${fqdn}";
      LUNA_OWNER = "@${username}:${fqdn}";
      LUNA_OWNER_TIMEZONE = site.ownerTimeZone;
      LUNA_BRIEF_TIME = site.briefTime;
      LUNA_MODEL = "claude-opus-5-5";
      LUNA_EFFORT = "medium";
      LUNA_MONEY = if site.money then "1" else "0";
      LUNA_WISE = builtins.toJSON site.wise;
      LUNA_OWNER_LOGIN = site.ownerLogin;
      LUNA_WEB_ORIGIN = "https://${fqdn}:8443";
      LUNA_WEB_PORT = "8090";
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
      # Wait longer after each failure: 30 s, then up to 10 min. A fast
      # restart loop makes many failed Matrix logins, and Synapse then
      # refuses all logins for some minutes.
      Restart = "on-failure";
      RestartSec = 30;
      RestartSteps = 5;
      RestartMaxDelaySec = 600;

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
