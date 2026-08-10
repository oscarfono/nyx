{ config, pkgs, lib, ... }:

# Small generated utilities. Each is a Nix-built script, not a file you edit
# on the machine, so they are reproducible and versioned with everything else.

let
  # Screen recording with a stop toggle, so one keybind does both.
  nyx-record = pkgs.writeShellScriptBin "nyx-record" ''
    set -eu
    if pgrep -x wf-recorder >/dev/null; then
      pkill -INT wf-recorder
      ${pkgs.libnotify}/bin/notify-send "Recording stopped" "Saved to ~/Videos"
    else
      mkdir -p "$HOME/Videos"
      OUT="$HOME/Videos/rec-$(date +%Y%m%d-%H%M%S).mp4"
      ${pkgs.libnotify}/bin/notify-send "Recording" "SUPER+SHIFT+R again to stop"
      ${pkgs.wf-recorder}/bin/wf-recorder -g "$(${pkgs.slurp}/bin/slurp)" -f "$OUT"
    fi
  '';

  # Screenshots. These exist as scripts rather than inline in the keybind
  # because the command contains quotes and $(...), which have to survive a
  # Nix string, then a Lua string, then the shell. Three layers of escaping
  # is how the last Hyprland config broke. A script is one layer.
  nyx-shot = pkgs.writeShellScriptBin "nyx-shot" ''
    set -eu
    NOTIFY=${pkgs.libnotify}/bin/notify-send
    GRIM=${pkgs.grim}/bin/grim
    COPY=${pkgs.wl-clipboard}/bin/wl-copy
    OUT="$HOME/Pictures/screenshots"
    mkdir -p "$OUT"
    FILE="$OUT/shot-$(date +%Y%m%d-%H%M%S).png"

    geom_region() { ${pkgs.slurp}/bin/slurp; }
    geom_window() {
      ${pkgs.hyprland}/bin/hyprctl -j activewindow \
        | ${pkgs.jq}/bin/jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
    }

    case "''${1:-clipboard}" in
      clipboard) $GRIM -g "$(geom_region)" - | $COPY
                 $NOTIFY "Screenshot" "Region copied to clipboard" ;;
      edit)      $GRIM -g "$(geom_region)" - | ${pkgs.satty}/bin/satty -f - ;;
      window)    $GRIM -g "$(geom_window)" - | $COPY
                 $NOTIFY "Screenshot" "Window copied to clipboard" ;;
      screen)    $GRIM - | $COPY
                 $NOTIFY "Screenshot" "Screen copied to clipboard" ;;
      save)      $GRIM -g "$(geom_region)" "$FILE"
                 $NOTIFY "Screenshot" "Saved to $FILE" ;;
      *)         echo "usage: nyx-shot [clipboard|edit|window|screen|save]" >&2
                 exit 1 ;;
    esac
  '';

  nyx-dpms = pkgs.writeShellScriptBin "nyx-dpms" ''
    exec ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.dpms({ state = \"''${1:-on}\" })"
  '';

  # Reminders, using systemd rather than a daemon of its own.
  #   nyx-remind 25m "stand up"
  # systemd-run --user schedules a transient timer; nothing persists, nothing
  # needs a background process, and `systemctl --user list-timers` shows them.
  nyx-remind = pkgs.writeShellScriptBin "nyx-remind" ''
    set -eu
    WHEN="''${1:-}"
    shift || true
    MSG="''${*:-Reminder}"
    if [ -z "$WHEN" ]; then
      echo "usage: nyx-remind <delay, e.g. 25m|1h|90s> <message>" >&2
      exit 1
    fi
    ${pkgs.systemd}/bin/systemd-run --user --on-active="$WHEN" \
      --unit="nyx-remind-$(date +%s)" \
      ${pkgs.libnotify}/bin/notify-send -u critical "Reminder" "$MSG"
    ${pkgs.libnotify}/bin/notify-send "Reminder set" "$WHEN: $MSG"
  '';

  # Prompt for a reminder through the menu picker.
  #
  # Careful in here: inside a Nix indented string, two single quotes are the
  # escape character, so they cannot appear literally in the script OR in a
  # comment within it. That is why the picker is fed by echo rather than an
  # empty printf.
  nyx-remind-prompt = pkgs.writeShellScriptBin "nyx-remind-prompt" ''
    set -eu
    when=$(printf '5m\n10m\n25m\n1h\n2h\n' | ${pkgs.walker}/bin/walker --dmenu -p "Remind me in")
    [ -z "$when" ] && exit 0
    msg=$(echo | ${pkgs.walker}/bin/walker --dmenu -p "About what")
    ${nyx-remind}/bin/nyx-remind "$when" "$msg"
  '';

  # Idle inhibit. hypridle is a user service, so stopping it is the whole
  # mechanism: no daemon to talk to, nothing to get out of sync.
  nyx-caffeine = pkgs.writeShellScriptBin "nyx-caffeine" ''
    set -eu
    STATE="''${XDG_STATE_HOME:-$HOME/.local/state}/nyx"
    mkdir -p "$STATE"
    if systemctl --user is-active --quiet hypridle; then
      systemctl --user stop hypridle
      touch "$STATE/caffeine"
      ${pkgs.libnotify}/bin/notify-send "Caffeine on" "Screen will not lock or sleep"
    else
      systemctl --user start hypridle
      rm -f "$STATE/caffeine"
      ${pkgs.libnotify}/bin/notify-send "Caffeine off" "Idle timers restored"
    fi
    pkill -SIGRTMIN+9 waybar 2>/dev/null || true
  '';

  # Waybar reads this. Exit 0 with JSON either way.
  nyx-caffeine-status = pkgs.writeShellScriptBin "nyx-caffeine-status" ''
    if systemctl --user is-active --quiet hypridle; then
      printf '{"text":"","tooltip":"Idle timers active","class":"off"}\n'
    else
      printf '{"text":"","tooltip":"Caffeine: screen will not lock","class":"on"}\n'
    fi
  '';

  # Health check. Everything on this list has silently gone wrong at least
  # once. Read-only: it reports, it never changes anything.
  nyx-doctor = pkgs.writeShellScriptBin "nyx-doctor" ''
    ok()   { printf '  \033[32m ok  \033[0m %s\n' "$*"; }
    warn() { printf '  \033[33mwarn \033[0m %s\n' "$*"; }
    bad()  { printf '  \033[31mFAIL \033[0m %s\n' "$*"; }

    echo
    echo "nyx doctor"
    echo

    echo "generation"
    cur=$(readlink -f /run/current-system)
    prof=$(readlink -f /nix/var/nix/profiles/system)
    if [ "$cur" = "$prof" ]; then
      ok "running a switched generation"
    else
      bad "running a TEST generation — a reboot will revert it. Run: sudo nixos-rebuild switch --flake ~/Projects/nyx#$(hostname)"
    fi

    echo
    echo "boot"
    if command -v sbctl >/dev/null; then
      if sbctl verify 2>/dev/null | grep -q "is not signed.*Linux/"; then
        bad "a UKI under /boot/EFI/Linux is unsigned — do NOT reboot with Secure Boot enforcing"
      else
        ok "all UKIs signed (the raw kernel showing unsigned is correct)"
      fi
      sbctl status 2>/dev/null | grep -q "Secure Boot:.*Enabled" \
        && ok "secure boot enforcing" || warn "secure boot not enforcing"
    fi
    used=$(df --output=pcent /boot 2>/dev/null | tail -1 | tr -dc '0-9')
    if [ -n "''${used:-}" ]; then
      [ "$used" -lt 80 ] && ok "/boot at ''${used}%" || bad "/boot at ''${used}% — a rebuild may fail partway through"
    fi

    echo
    echo "backups"
    # ExecMainExitTimestamp is cleared once the unit resets, so ask the
    # TIMER when it last fired rather than the service when it last exited.
    # No sudo needed for either.
    trig=$(systemctl show restic-backups-$(hostname).timer -p LastTriggerUSec --value 2>/dev/null || true)
    if [ -n "''${trig:-}" ] && [ "$trig" != "n/a" ]; then
      last=$(date -d "$trig" +%s 2>/dev/null || echo 0)
      age=$(( ($(date +%s) - last) / 86400 ))
      if [ "$age" -le 2 ]; then ok "last backup run ''${age}d ago"
      else bad "last backup run ''${age}d ago"; fi
    else
      nxt=$(systemctl show restic-backups-$(hostname).timer -p NextElapseUSecRealtime --value 2>/dev/null || true)
      if [ -n "''${nxt:-}" ]; then
        warn "timer armed but has not fired yet (next: $nxt)"
      else
        bad "no backup timer found"
      fi
    fi
    if systemctl is-failed --quiet restic-backups-$(hostname).service 2>/dev/null; then
      bad "the last backup run FAILED: journalctl -u restic-backups-$(hostname)"
    fi

    echo
    echo "services"
    f=$(systemctl --failed --no-legend | wc -l)
    [ "$f" -eq 0 ] && ok "no failed system units" || bad "$f failed system unit(s): systemctl --failed"
    fu=$(systemctl --user --failed --no-legend | wc -l)
    [ "$fu" -eq 0 ] && ok "no failed user units" || bad "$fu failed user unit(s): systemctl --user --failed"

    echo
    echo "bits that break quietly"
    [ -d "$HOME/.emacs.d/straight/build/eat/terminfo" ] \
      && ok "eat terminfo present" || warn "eat terminfo missing — keystrokes will duplicate"
    [ -f "$HOME/.local/share/whisper/ggml-small.en.bin" ] || [ -f "$HOME/.local/share/whisper/ggml-base.en.bin" ] \
      && ok "whisper model present" || warn "whisper model not downloaded — SUPER+D will fail"
    [ -f "$HOME/.config/sops/age/keys.txt" ] \
      && ok "personal age key present" || bad "no personal age key — only this machine can decrypt secrets"
    systemctl --user is-active --quiet hypridle \
      && ok "idle timers active" || warn "hypridle stopped (caffeine on?)"

    echo
  '';
in
{
  home.packages = [
    nyx-shot
    nyx-record
    nyx-caffeine
    nyx-caffeine-status
    nyx-doctor
    pkgs.jq
    nyx-remind
    nyx-remind-prompt

    # AirDrop-equivalent. Cross-platform, LAN-only, no account, no cloud.
    # There is a macOS client, so this is the path for getting files off the
    # MacBook. See the note in SUMMARY.md about SSH keys specifically.
    pkgs.localsend

    pkgs.libnotify
  ];

  # LocalSend needs its port open to receive. Sending works without it.
  # The firewall rule lives in modules/desktop.nix so it is a system-level,
  # reviewable decision rather than something buried in the user config.
}
