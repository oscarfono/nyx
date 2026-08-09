{ config, pkgs, lib, ... }:

# Wallpaper. Images live in the repo under assets/wallpapers and are copied
# into the store, so a fresh machine gets them with the rebuild rather than
# needing a separate download.
#
# nyx-wallpaper is generated, not hand-written:
#   nyx-wallpaper next   cycle to the next image
#   nyx-wallpaper pick   choose one from the menu picker
#   nyx-wallpaper set X  set a specific path

# Wallpaper. Images live in the repo under assets/wallpapers and are copied
# into the store, so a fresh machine gets them with the rebuild.
#
# swaybg, not hyprpaper. hyprpaper kept reporting "Monitor eDP-1 has no
# target" while its IPC rejected every request, which left no way to set or
# query a wallpaper. swaybg has no IPC and no daemon protocol: it draws one
# image and exits when told to. Changing wallpaper is therefore "write the
# path, restart the unit", which cannot get into a half-configured state.
#
#   nyx-wallpaper next   cycle to the next image
#   nyx-wallpaper pick   choose one from the menu picker
#   nyx-wallpaper set X  set a specific path

let
  wallpapers = [
    ../assets/wallpapers/bull-bear.png
    ../assets/wallpapers/dark-abstract.png
    ../assets/wallpapers/earth-space.jpg
    ../assets/wallpapers/full-moon-forest.jpg
  ];

  storePaths = map (w: "${w}") wallpapers;
  first = builtins.elemAt storePaths 0;

  picker = "${pkgs.walker}/bin/walker --dmenu";

  nyx-wallpaper = pkgs.writeShellScriptBin "nyx-wallpaper" ''
    set -eu
    STATE="''${XDG_STATE_HOME:-$HOME/.local/state}/nyx"
    mkdir -p "$STATE"
    CURRENT="$STATE/wallpaper"

    list() { printf '%s\n' ${lib.escapeShellArgs storePaths}; }

    apply() {
      printf '%s\n' "$1" > "$CURRENT"
      systemctl --user restart nyx-wallpaper.service
    }

    case "''${1:-next}" in
      next)
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
      current)
        cat "$CURRENT" 2>/dev/null || echo "${first}"
        ;;
      *)
        echo "usage: nyx-wallpaper [next|pick|set PATH|current]" >&2
        exit 1
        ;;
    esac
  '';
in
{
  home.packages = [ nyx-wallpaper pkgs.swaybg ];

  systemd.user.services.nyx-wallpaper = {
    Unit = {
      Description = "Wallpaper (swaybg)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      # Reads the state file each start, so nyx-wallpaper only has to write
      # a path and restart this unit.
      ExecStart = toString (pkgs.writeShellScript "nyx-wallpaper-start" ''
        IMG=$(cat "''${XDG_STATE_HOME:-$HOME/.local/state}/nyx/wallpaper" 2>/dev/null || echo "${first}")
        [ -f "$IMG" ] || IMG="${first}"
        exec ${pkgs.swaybg}/bin/swaybg -m fill -i "$IMG"
      '');
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
