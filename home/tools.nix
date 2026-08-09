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
in
{
  home.packages = [
    nyx-record
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
