{ config, pkgs, lib, ... }:

# Wallpaper.
#
# Two halves, deliberately:
#
#   DEFAULT   assets/dark-abstract.png, committed to the repo and copied
#             into the store. A fresh machine has a correct wallpaper on
#             first boot with nothing to set up, and it can never point at
#             a file that does not exist.
#
#   LIBRARY   ~/Pictures/wallpapers, an ordinary directory. Drop images in
#             and they appear in the picker immediately, no rebuild. The
#             repo's wallpapers are seeded there on first activation so the
#             directory is never empty.
#
# swaybg rather than hyprpaper: no IPC, no daemon protocol, so changing
# wallpaper is "write the path, restart the unit" and cannot end up in a
# half-configured state.
#
#   nyx-wallpaper next      cycle through the library
#   nyx-wallpaper pick      thumbnail browser (yazi in a Ghostty window)
#   nyx-wallpaper set PATH  set a specific file
#   nyx-wallpaper current   print the current path

let
  # Shipped with the repo. This one is the fallback and can never be missing.
  defaultWallpaper = "${../assets/wallpapers/dark-abstract.png}";

  seeded = [
    ../assets/wallpapers/dark-abstract.png
    ../assets/wallpapers/full-moon-forest.jpg
    ../assets/wallpapers/earth-space.jpg
    ../assets/wallpapers/bull-bear.png
  ];

  library = "${config.home.homeDirectory}/Pictures/wallpapers";

  nyx-wallpaper = pkgs.writeShellScriptBin "nyx-wallpaper" ''
    set -eu
    STATE="''${XDG_STATE_HOME:-$HOME/.local/state}/nyx"
    mkdir -p "$STATE"
    CURRENT="$STATE/wallpaper"
    LIB="${library}"

    list() {
      find "$LIB" -maxdepth 1 -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
        | sort
    }

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
        [ -n "$next" ] && apply "$next"
        ;;

      pick)
        # yazi previews images inline; Ghostty speaks the kitty graphics
        # protocol, so these are real thumbnails. --chooser-file makes yazi
        # return the selection rather than opening it.
        SEL=$(mktemp)
        ${pkgs.ghostty}/bin/ghostty --title=nyx-wallpaper \
          -e ${pkgs.yazi}/bin/yazi --chooser-file="$SEL" "$LIB" || true
        choice=$(cat "$SEL" 2>/dev/null || true)
        rm -f "$SEL"
        [ -n "$choice" ] && [ -f "$choice" ] && apply "$choice"
        ;;

      set)
        [ -f "$2" ] || { echo "no such file: $2" >&2; exit 1; }
        apply "$2"
        ;;

      current)
        cat "$CURRENT" 2>/dev/null || printf '%s\n' "${defaultWallpaper}"
        ;;

      *)
        echo "usage: nyx-wallpaper [next|pick|set PATH|current]" >&2
        exit 1
        ;;
    esac
  '';
in
{
  home.packages = [ nyx-wallpaper pkgs.swaybg pkgs.yazi ];

  # Seed the library from the repo. `C` copies only if the target does not
  # exist, so anything you add or delete afterwards is left alone.
  systemd.user.tmpfiles.rules =
    [ "d ${library} 0755 - - -" ]
    ++ map (w: "C ${library}/${builtins.baseNameOf w} 0644 - - ${w}") seeded;

  systemd.user.services.nyx-wallpaper = {
    Unit = {
      Description = "Wallpaper (swaybg)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = toString (pkgs.writeShellScript "nyx-wallpaper-start" ''
        IMG=$(cat "''${XDG_STATE_HOME:-$HOME/.local/state}/nyx/wallpaper" 2>/dev/null || true)
        [ -n "$IMG" ] && [ -f "$IMG" ] || IMG="${defaultWallpaper}"
        exec ${pkgs.swaybg}/bin/swaybg -m fill -i "$IMG"
      '');
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
