{ config, pkgs, lib, ... }:

# Renders lib/menu.nix into a set of Walker-driven dispatch scripts.
#
# Every submenu becomes its own script, generated at build time. There is no
# hand-written menu bash anywhere in this repo: change the tree in
# lib/menu.nix and rebuild.

let
  t = import ../lib/melancholy.nix;
  tree = import ../lib/menu.nix { inherit pkgs lib; };

  # Walker in dmenu mode is the picker. If walker is unavailable or you
  # prefer something smaller, swapping this one line to
  #   "${pkgs.fuzzel}/bin/fuzzel --dmenu"
  # changes every menu at once.
  picker = "${pkgs.walker}/bin/walker --dmenu";

  # Menu labels carry nerd-font glyphs and spaces. Reduce to a safe id.
  slug = name:
    let chars = lib.stringToCharacters name;
        kept = builtins.filter (c: builtins.match "[A-Za-z]" c != null) chars;
    in lib.toLower (lib.concatStrings kept);

  # One script per menu level.
  mkMenu = id: label: items:
    let
      entries = lib.concatStringsSep "\\n" (lib.attrNames items);

      cases = lib.concatStringsSep "\n      " (lib.mapAttrsToList (k: v:
        let target =
          if v ? submenu
          then "nyx-menu-${id}-${slug k}"
          else v.exec;
        in ''${lib.escapeShellArg k}) ${target} ;;'') items);
    in
    pkgs.writeShellScriptBin "nyx-menu-${id}" ''
      set -eu
      choice=$(printf '${entries}\n' | ${picker} -p ${lib.escapeShellArg label})
      [ -z "$choice" ] && exit 0
      case "$choice" in
      ${cases}
      esac
    '';

  # Walk the tree, producing a flat list of scripts.
  collect = id: label: items:
    [ (mkMenu id label items) ]
    ++ lib.concatLists (lib.mapAttrsToList (k: v:
        if v ? submenu
        then collect "${id}-${slug k}" k v.submenu
        else [ ]) items);

  scripts = collect "root" "Nyx" tree;
in
{
  home.packages = scripts ++ [ pkgs.walker pkgs.bluetuith pkgs.wlr-randr ];

  # Walker's own styling, so the menu matches everything else.
  xdg.configFile."walker/themes/melancholy.css".text = ''
    #window { background: ${t.bg}; color: ${t.fg}; }
    #box    { border: 2px solid ${t.amber}; border-radius: 8px; padding: 8px; }
    #search { background: ${t.bgSubtle}; color: ${t.fg}; padding: 6px; }
    #item:selected { background: ${t.bgSubtle}; color: ${t.amber}; }
    #text   { font-family: "CommitMono Nerd Font Mono"; font-size: 12px; }
  '';
}
