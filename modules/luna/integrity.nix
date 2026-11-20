{ pkgs, lib, site, ... }:
let
  state = "/var/lib/luna-integrity";
  path = lib.makeBinPath (with pkgs; [ coreutils diffutils findutils gnugrep gnused gawk jq curl systemd nix util-linux ]);

  # Post a text to the core API: "alert" (one line) or "notice" (a long text).
  post = pkgs.writeShellScript "luna-post" ''
    export PATH=${path}
    kind=$1; text=$2
    jq -n --arg t "$text" '{text: $t}' \
      | curl -sS --max-time 15 --unix-socket /run/luna-api/api.sock -H 'content-type: application/json' \
          --data-binary @- -o /dev/null "http://core/api/$kind" \
      || echo "luna-integrity: the core did not take the $kind: $text" >&2
  '';

  # The files an attacker changes to stay on a host. Each line: the hash and the path.
  manifest = pkgs.writeShellScript "luna-manifest" ''
    export PATH=${path}
    {
      # Files with the setuid or setgid bit, outside the Nix store.
      find / -xdev \( -path /nix -o -path /proc -o -path /sys \) -prune -o -type f -perm /6000 -print 2>/dev/null
      # Keys, accounts, sudo and the SSH configuration.
      for f in /root/.ssh/authorized_keys /etc/sudoers /etc/passwd /etc/shadow /etc/group /etc/ssh/sshd_config; do
        [ -e "$f" ] && echo "$f"
      done
      find /etc/ssh/authorized_keys.d /root/.ssh -type f 2>/dev/null
      # Units and timers outside the Nix store, and cron.
      find /etc/systemd/system /etc/systemd/user /etc/cron.d /var/spool/cron -type f 2>/dev/null
    } | sort -u | while read -r f; do sha256sum "$f" 2>/dev/null || echo "unreadable  $f"; done
  '';

  check = pkgs.writeShellScript "luna-integrity" ''
    export PATH=${path}
    set -u
    changed=$(diff ${state}/baseline <(${manifest}) | grep -E '^[<>]' | awk '{print $NF}' | sort -u | paste -sd ' ' || true)
    current=$(readlink -f /run/current-system)
    expected=$(cat ${state}/expected-system 2>/dev/null || echo none)
    # Each store path against the hash from its build.
    bad=$(nix-store --verify --check-contents 2>&1 | grep -c "was modified" || true)

    system_ok=true
    [ "$current" = "$expected" ] || system_ok=false

    jq -n --arg time "$(date -u +%FT%TZ)" --arg changed "$changed" --argjson bad "$bad" \
          --argjson system_ok "$system_ok" --arg current "$current" \
          '{time: $time, changed: $changed, store_modified: $bad, system_ok: $system_ok, system: $current}' \
          > ${state}/last.json

    if [ -n "$changed" ]; then ${post} alert "Integrity: changed since the last deploy: $changed"; fi
    if [ "$bad" -gt 0 ]; then ${post} alert "Integrity: $bad Nix store paths do not match their hash."; fi
    if [ "$system_ok" != true ]; then ${post} alert "Integrity: the running system is not the system of the last deploy."; fi
  '';

  brief = pkgs.writeShellScript "luna-security-brief" ''
    export PATH=${path}
    set -u
    since=$(date -u -d '-24 hours' +%FT%T)

    logins=$(journalctl -u tailscaled --since -24h -o cat 2>/dev/null \
      | sed -nE 's/.*audit: SSH login: user=([^ ]+).*node=([^.]+).*/\1 from \2/p' \
      | sort | uniq -c | awk '{c=$1; $1=""; printf "%s%s (%d)", (n++ ? ", " : ""), substr($0,2), c}')
    alerts=$(jq -r --arg s "$since" 'select(.event == "alert" and .time >= $s) | .text' /var/lib/luna/audit/audit.jsonl 2>/dev/null | wc -l)
    refused=$(journalctl -u tinyproxy --since -24h -o cat 2>/dev/null | grep -ci refused || true)
    kills=$(journalctl -k --since -24h -o cat 2>/dev/null | grep -c 'type=1326' || true)
    failures=$(journalctl --since -24h -o cat 2>/dev/null | grep -c 'Failed with result' || true)
    failed_now=$(systemctl --failed --plain --no-legend 2>/dev/null | awk '{print $1}' | paste -sd ' ')
    if [ -f ${state}/last.json ]; then
      integrity=$(jq -r 'if (.changed == "" and .store_modified == 0 and .system_ok) then "clean (\(.time))" else "PROBLEMS: changed [\(.changed)], store \(.store_modified), system ok \(.system_ok)" end' ${state}/last.json)
    else
      integrity="no check yet"
    fi
    version=$(cat /run/current-system/nixos-version)
    built=$(echo "$version" | sed -nE 's/.*\.([0-9]{4})([0-9]{2})([0-9]{2})\..*/\1-\2-\3/p')
    if [ -n "$built" ]; then
      nixpkgs="$built, $(( ( $(date +%s) - $(date -d "$built" +%s) ) / 86400 )) days old"
    else
      nixpkgs="unknown ($version)"
    fi
    deployed=$(date -r /nix/var/nix/profiles/system '+%Y-%m-%d %H:%M %Z' 2>/dev/null || echo unknown)
    disk=$(df -h --output=pcent,avail / | tail -1 | awk '{print $1 " used, " $2 " free"}')

    text="**Security brief, $(date '+%A %-d %B')**

    - SSH logins: ''${logins:-none}
    - Alerts: $alerts in 24 hours
    - Egress refused: $refused
    - Sandbox kills: $kills
    - Unit failures: $failures in 24 hours. Failed now: ''${failed_now:-none}
    - Integrity: $integrity
    - nixpkgs: $nixpkgs
    - Last deploy: $deployed
    - Disk: $disk"
    ${post} notice "$(printf '%s\n' "$text" | sed -E 's/^    //')"
  '';

  hardened = {
    Type = "oneshot";
    Nice = 19;
    IOSchedulingClass = "idle";
    ProtectHome = "read-only";
    PrivateTmp = true;
    NoNewPrivileges = true;
    # The core API is a unix socket: no network.
    IPAddressDeny = "any";
    RestrictAddressFamilies = [ "AF_UNIX" ];
  };
in
{
  # Each activation (a deploy or a boot) records what is expected.
  # Activation is the only expected path for a change to these files.
  system.activationScripts.luna-integrity-baseline = {
    deps = [ "users" "etc" ];
    text = ''
      mkdir -p ${state}
      chmod 0700 ${state}
      ${manifest} > ${state}/baseline
      echo "$systemConfig" > ${state}/expected-system
    '';
  };

  # B3: each night, the integrity check (as root, but read-only and with no network).
  systemd.services.luna-integrity = {
    description = "LUNA blue team: the integrity check";
    serviceConfig = hardened // {
      ExecStart = check;
      TimeoutStartSec = "3h";
      ReadWritePaths = [ state ];
      ProtectSystem = "strict";
    };
  };
  systemd.timers.luna-integrity = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*-*-* 03:30:00 ${site.ownerTimeZone}"; Persistent = true; };
  };

  # B4: each morning, the security brief.
  systemd.services.luna-security-brief = {
    description = "LUNA blue team: the daily security brief";
    serviceConfig = hardened // { ExecStart = brief; ProtectSystem = "strict"; };
  };
  systemd.timers.luna-security-brief = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*-*-* 07:05:00 ${site.ownerTimeZone}"; Persistent = true; };
  };
}
