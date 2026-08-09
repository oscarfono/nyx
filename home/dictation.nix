{ config, pkgs, lib, ... }:

# Voice dictation. Toggle with SUPER+D: speak, press again, text lands in the
# clipboard and is typed into the focused window.
#
# whisper.cpp runs entirely on this machine. Nothing is sent anywhere.
#
# The model is NOT a build input. It is ~150MB of weights fetched at first
# use by a user service, because baking it into the closure would bloat every
# rebuild and pin a blob into the store.

let
  # base.en: English-only, fast enough on a T490's CPU to be usable.
  # Swap to small.en for better accuracy at roughly 3x the time.
  model = "base.en";
  modelDir = "${config.home.homeDirectory}/.local/share/whisper";
  modelFile = "${modelDir}/ggml-${model}.bin";

  nyx-dictate = pkgs.writeShellScriptBin "nyx-dictate" ''
    set -eu
    STATE="''${XDG_RUNTIME_DIR:-/tmp}/nyx-dictate"
    WAV="$STATE/clip.wav"
    mkdir -p "$STATE"

    notify() { ${pkgs.libnotify}/bin/notify-send -a dictation "$@"; }

    # Second press: stop recording and transcribe.
    if [ -f "$STATE/pid" ] && kill -0 "$(cat "$STATE/pid")" 2>/dev/null; then
      kill -INT "$(cat "$STATE/pid")" 2>/dev/null || true
      rm -f "$STATE/pid"
      sleep 0.3
      notify "Transcribing..."

      if [ ! -f "${modelFile}" ]; then
        notify -u critical "No model" "Run: systemctl --user start nyx-whisper-model"
        exit 1
      fi

      TEXT=$(${pkgs.whisper-cpp}/bin/whisper-cli \
               -m "${modelFile}" -f "$WAV" -nt -np 2>/dev/null \
             | tr '\n' ' ' | sed 's/^ *//; s/ *$//')

      if [ -z "$TEXT" ]; then
        notify "Nothing heard"
        exit 0
      fi

      printf '%s' "$TEXT" | ${pkgs.wl-clipboard}/bin/wl-copy
      ${pkgs.wtype}/bin/wtype "$TEXT" 2>/dev/null || \
        notify "Copied to clipboard" "$TEXT"
      exit 0
    fi

    # First press: start recording.
    notify "Listening" "SUPER+D again to stop"
    ${pkgs.sox}/bin/rec -q -r 16000 -c 1 -b 16 "$WAV" &
    echo $! > "$STATE/pid"
  '';
in
{
  home.packages = [
    nyx-dictate
    pkgs.whisper-cpp
    pkgs.sox
    pkgs.wtype          # types into the focused window under Wayland
  ];

  # Fetch the model once, in the background, after the network is up.
  # Same rule as the Emacs bootstrap: never in an activation script.
  systemd.user.services.nyx-whisper-model = {
    Unit = {
      Description = "Download the whisper ${model} model";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = toString (pkgs.writeShellScript "nyx-whisper-model" ''
        set -u
        [ -f "${modelFile}" ] && exit 0
        mkdir -p "${modelDir}"
        ${pkgs.curl}/bin/curl -fsSL --retry 3 \
          -o "${modelFile}.part" \
          "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${model}.bin" \
          && mv "${modelFile}.part" "${modelFile}" \
          || { echo "nyx: whisper model download failed, will retry next boot" >&2; rm -f "${modelFile}.part"; }
        exit 0
      '');
    };
    Install.WantedBy = [ "default.target" ];
  };
}
