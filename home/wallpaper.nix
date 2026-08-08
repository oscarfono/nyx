{ config, pkgs, lib, ... }:

# Wallpaper. Images live in the repo under assets/wallpapers and are copied
# into the store, so a fresh machine gets them with the rebuild rather than
# needing a separate download.
#
# nyx-wallpaper is generated, not hand-written:
#   nyx-wallpaper next   cycle to the next image
#   nyx-wallpaper pick   choose one from the menu picker
#   nyx-wallpaper set X  set a specific path

let
  t = import ../lib/melancholy.nix;

  wallpapers = [
    ../assets/wallpapers/melancholy-dusk.png
    ../assets/wallpapers/melancholy-contour.png
  ];

  # Copy each into the store and keep the paths for the script.
  storePaths = map (w: "${w}") wallpapers;
  pathList = lib.concatStringsSep "\n" storePaths;

  picker = "${pkgs.walker}/bin/walker --dmenu";

  nyx-wallpaper = pkgs.writeShellScriptBin "nyx-wallpaper" ''
    set -eu
    STATE="''${XDG_STATE_HOME:-$HOME/.local/state}/nyx"
    mkdir -p "$STATE"
    CURRENT="$STATE/wallpaper"

    apply() {
      ${pkgs.hyprland}/bin/hyprctl hyprpaper preload "$1" >/dev/null
      for m in $(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[].name'); do
        ${pkgs.hyprland}/bin/hyprctl hyprpaper wallpaper "$m,$1" >/dev/null
      done
      printf '%s\n' "$1" > "$CURRENT"
    }

    list() { printf '%s\n' ${lib.escapeShellArgs storePaths}; }

    case "''${1:-next}" in
      next)
        # `A || B && C` in POSIX sh does not mean what it looks like, so the
        # selection is written out explicitly.
        cur=$(cat "$CURRENT" 2>/dev/null || true)
        next=$(list | grep -A1 -x -F "$cur" 2>/dev/null | tail -1 || true)
        if [ -z "$next" ] || [ "$next" = "$cur" ]; then
          next=$(list | head -1)
        fi
        apply "$next"
        ;;
      pick)
        choice=$(list | ${picker} -p "Wallpaper")
        [ -n "$choice" ] && apply "$choice"
        ;;
      set)
        apply "$2"
        ;;
      *)
        echo "usage: nyx-wallpaper [next|pick|set PATH]" >&2
        exit 1
        ;;
    esac
  '';
in
{
  home.packages = [ nyx-wallpaper pkgs.jq ];

  # hyprpaper preloads both and sets the first at login. nyx-wallpaper takes
  # over from there at runtime via hyprctl.
  services.hyprpaper = {
    enable = true;
    settings = {
      ipc = "on";
      splash = false;
      preload = storePaths;
      wallpaper = [ ",${builtins.elemAt storePaths 0}" ];
    };
  };
}
