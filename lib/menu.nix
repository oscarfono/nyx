# Nyx menu tree.
#
# Omarchy's menu is a pile of bash. This is the same idea as data: a nested
# attribute set that gets rendered into dispatch scripts at build time. Add
# an entry here and it appears in the menu after a rebuild. Nothing at
# runtime reads or writes this.
#
# Leaf nodes have `exec`. Branch nodes have `submenu`. That is the whole
# schema.

{ pkgs, lib, ... }:

let
  webapps = import ./webapps.nix;

  # The Web submenu is GENERATED from lib/webapps.nix rather than listed
  # here. Two hand-maintained lists of the same thing drift within a week:
  # add a web app there and it appears in both the launcher and this menu.
  webMenu = lib.mapAttrs' (key: app: {
    name = "󰖟  ${app.name}";
    value.exec = ''brave --app="${app.url}" --class="${app.class}"'';
  }) webapps;
in

{
  # Applications, grouped. This is for DISCOVERY — "what do I have for
  # X" — not for launching things you already know the name of. Type the
  # name into fuzzel (SUPER+Space) for that; fuzzy search over a flat list
  # beats navigating a tree every time.
  "󰀻  Apps" = {
    submenu = {
      "󰖟  Web" = { submenu = webMenu; };

      "󰅩  Development" = {
        submenu = {
          "󰘳  Emacs"        = { exec = "emacsclient -c -a emacs"; };
          "󰀵  Claude Code"  = { exec = "ghostty --working-directory=$HOME/Projects -e claude"; };
          "󰊢  Lazygit"      = { exec = "ghostty -e lazygit"; };
          "󰡨  Lazydocker"   = { exec = "ghostty -e lazydocker"; };
          "󱃾  k9s"          = { exec = "ghostty -e k9s"; };
          "󰆼  psql (msf)"   = { exec = "ghostty -e psql -d msf"; };
        };
      };

      "󰒃  Security" = {
        submenu = {
          "󰯅  Burp Suite"   = { exec = "burpsuite"; };
          "󰯅  OWASP ZAP"    = { exec = "zap"; };
          "󰆧  Metasploit"   = { exec = "ghostty -e msfconsole"; };
          "󰛳  Wireshark"    = { exec = "wireshark"; };
          "󰛳  nmap"         = { exec = "ghostty -e sh -c 'read -p \"target: \" t; nmap -A \"$t\" | less'"; };
          "󰒃  Vulnix scan"  = { exec = "ghostty -e sh -c 'vulnix --system | less'"; };
        };
      };

      "󰎆  Media" = {
        submenu = {
          "󰕾  Audio mixer"  = { exec = "pavucontrol"; };
          "󰋩  Image viewer" = { exec = "imv"; };
          "󰕧  mpv"          = { exec = "mpv"; };
          "󰓓  Steam"        = { exec = "steam"; };
        };
      };

      "󰉋  System" = {
        submenu = {
          "󰉋  Files"        = { exec = "nautilus"; };
          "󰌾  KeePassXC"    = { exec = "keepassxc"; };
          "󰃬  Calculator"   = { exec = "qalculate-gtk"; };
          "󰈹  Firefox"      = { exec = "firefox"; };
          "󰖟  Brave"        = { exec = "brave"; };
          "󰆍  Terminal"     = { exec = "ghostty"; };
        };
      };
    };
  };

  "󰸉  Style" = {
    submenu = {
      "  Wallpaper next" = { exec = "nyx-wallpaper next"; };
      "  Wallpaper pick" = { exec = "nyx-wallpaper pick"; };
      "  Toggle bar"     = { exec = "pkill -SIGUSR1 waybar"; };
      "󰍹  Toggle idle lock" = { exec = "systemctl --user is-active hypridle && systemctl --user stop hypridle || systemctl --user start hypridle"; };
    };
  };

  "󰄀  Capture" = {
    submenu = {
      "  Region to clipboard" = { exec = "nyx-shot clipboard"; };
      "  Region to editor"    = { exec = "nyx-shot edit"; };
      "󰍹  Whole screen"        = { exec = "grim - | wl-copy"; };
      "  Record start/stop"   = { exec = "nyx-record"; };
    };
  };

  "󱐋  Tools" = {
    submenu = {
      "󰀵  Claude"          = { exec = "ghostty -e claude"; };
      "󰄄  Share a file"    = { exec = "localsend"; };
      "󰍬  Dictate"         = { exec = "nyx-dictate"; };
      "󰅐  Set a reminder"  = { exec = "nyx-remind-prompt"; };
      "󰕧  Record toggle"   = { exec = "nyx-record"; };
      "󰅶  Caffeine toggle" = { exec = "nyx-caffeine"; };
      "󰄬  Health check"    = { exec = "ghostty -e sh -c 'nyx-doctor; read -n1'"; };
      "󰅇  Clipboard history" = { exec = "sh -c 'cliphist list | walker --dmenu | cliphist decode | wl-copy'"; };
    };
  };

  "󰖩  Network" = {
    submenu = {
      "󰖩  Wifi"          = { exec = "ghostty -e nmtui"; };
      "󰂯  Bluetooth"     = { exec = "ghostty -e bluetuith"; };
      "󰇧  VPN status"    = { exec = "ghostty -e sh -c 'nmcli con show --active; read -n1'"; };
      "󰩠  Show IP"       = { exec = "ghostty -e sh -c 'ip -brief addr; read -n1'"; };
    };
  };

  "󰒓  System" = {
    submenu = {
      "  Audio"        = { exec = "pavucontrol"; };
      "󰍹  Displays"     = { exec = "ghostty -e wlr-randr"; };
      "  Battery"      = { exec = "ghostty -e sh -c 'acpi -V; read -n1'"; };
    };
  };

  "󰌾  Session" = {
    submenu = {
      "  Lock"      = { exec = "loginctl lock-session"; };
      "󰤄  Suspend"   = { exec = "systemctl suspend"; };
      "󰜉  Reboot"    = { exec = "systemctl reboot"; };
      "󰐥  Shutdown"  = { exec = "systemctl poweroff"; };
      "󰍃  Log out"   = { exec = "uwsm stop"; };
    };
  };

  "󰆧  Nix" = {
    submenu = {
      "󰏗  Search packages" = { exec = "ghostty -e sh -c 'read -p \"search: \" q; nix search nixpkgs \"$q\" | less'"; };
      "󰐊  Try a package"    = { exec = "ghostty -e sh -c 'read -p \"package: \" p; nix shell nixpkgs#\"$p\"'"; };
      "  Edit config"      = { exec = "emacsclient -c -a '' $HOME/Projects/nyx"; };
      "󰚰  Rebuild"          = { exec = "ghostty -e sh -c 'sudo nixos-rebuild switch --flake $HOME/Projects/nyx#$(hostname); read -n1'"; };
      "󰕌  Rollback"         = { exec = "ghostty -e sh -c 'sudo nixos-rebuild switch --rollback; read -n1'"; };
      "󰋼  Generations"      = { exec = "ghostty -e sh -c 'nixos-rebuild list-generations; read -n1'"; };
      "󰓦  Update inputs"    = { exec = "ghostty -e sh -c 'cd $HOME/Projects/nyx && nix flake update; read -n1'"; };
      "󰩹  Garbage collect"  = { exec = "ghostty -e sh -c 'sudo nix-collect-garbage -d; read -n1'"; };
      "󰒃  CVE scan (vulnix)" = { exec = "ghostty -e sh -c 'vulnix --system | less'"; };
    };
  };

  "󰋗  Learn" = {
    submenu = {
      "  Keybindings" = { exec = "ghostty -e less \"$HOME/.config/nyx/keybinds.txt\""; };
      "󰈙  Nyx README"  = { exec = "ghostty -e less \"$HOME/Projects/nyx/README.md\""; };
      "󰖟  NixOS options" = { exec = "brave https://search.nixos.org/options"; };
    };
  };
}
