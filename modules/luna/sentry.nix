{ pkgs, ... }:
let
  # luna-sentry (blue team, B2): it follows the journal and sends an alert to
  # the owner room for each event below. One alert for each key in each window,
  # so that a burst gives one alert. The core also limits alerts to 30 an hour.
  sentry = pkgs.writeShellApplication {
    name = "luna-sentry";
    runtimeInputs = [ pkgs.systemd pkgs.jq pkgs.curl pkgs.coreutils ];
    text = ''
      socket=/run/luna-api/api.sock
      declare -A last

      # send KEY WINDOW-SECONDS TEXT
      send() {
        local now
        now=$(date +%s)
        if [ -n "''${last[$1]:-}" ] && [ $((now - last[$1])) -lt "$2" ]; then
          return 0
        fi
        last[$1]=$now
        if ! jq -n --arg t "$3" '{text: $t}' \
          | curl -sS --max-time 10 --unix-socket "$socket" -H 'content-type: application/json' \
              --data-binary @- -o /dev/null http://core/api/alert; then
          echo "luna-sentry: the core did not take the alert: $3" >&2
        fi
      }

      journalctl --follow --lines=0 --output=json \
        | jq --unbuffered -r '[(.SYSLOG_IDENTIFIER // ""), (._TRANSPORT // ""), ((.MESSAGE // "") | tostring)] | @tsv' \
        | while IFS=$'\t' read -r ident transport msg; do
            # A Tailscale SSH login.
            if [[ $ident == tailscaled && $msg =~ audit:\ SSH\ login:\ user=([^ ]+).*from=([^ ]+).*ts_user=([^ ]+).*node=([^ ]+) ]]; then
              node=''${BASH_REMATCH[4]%%.*}
              send "ssh:''${BASH_REMATCH[1]}:$node" 1800 \
                "SSH login on luna: ''${BASH_REMATCH[1]}, from $node (''${BASH_REMATCH[3]}, ''${BASH_REMATCH[2]})."
            # A unit that failed.
            elif [[ $ident == systemd && $msg =~ ^([^:]+):\ Failed\ with\ result\ \'([^\']+)\' ]]; then
              send "unit:''${BASH_REMATCH[1]}" 600 "''${BASH_REMATCH[1]} failed (''${BASH_REMATCH[2]})."
            # A process that the seccomp filter of its unit killed.
            elif [[ $transport == kernel && $msg == *type=1326* && $msg =~ exe=\"([^\"]+)\".*syscall=([0-9]+) ]]; then
              exe=''${BASH_REMATCH[1]##*/}
              send "seccomp:$exe" 600 "The sandbox killed $exe (syscall ''${BASH_REMATCH[2]})."
            # A host or a port that the egress proxy refused (B1).
            elif [[ $ident == tinyproxy && $msg =~ [Rr]efused ]]; then
              detail=$(printf '%s' "$msg" | cut -c1-160)
              send "egress:$detail" 600 "Egress refused: $detail"
            fi
          done
    '';
  };
in
{
  systemd.services.luna-sentry = {
    description = "LUNA blue team: alerts from the journal to the owner room";
    after = [ "luna-core.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${sentry}/bin/luna-sentry";
      DynamicUser = true;
      # Read the journal. Write to the socket of the core API.
      SupplementaryGroups = [ "systemd-journal" "luna-api" ];
      Restart = "always";
      RestartSec = 10;

      # No network: the core API is a unix socket.
      IPAddressDeny = "any";
      RestrictAddressFamilies = [ "AF_UNIX" ];
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
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" "~@privileged" ];
    };
  };
}
