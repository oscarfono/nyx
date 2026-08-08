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

{
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
      "  Region to clipboard" = { exec = "grim -g \"$(slurp)\" - | wl-copy"; };
      "  Region to editor"    = { exec = "grim -g \"$(slurp)\" - | satty -f -"; };
      "󰍹  Whole screen"        = { exec = "grim - | wl-copy"; };
      "  Record region"       = { exec = "wf-recorder -g \"$(slurp)\" -f \"$HOME/Videos/rec-$(date +%s).mp4\""; };
      "  Stop recording"      = { exec = "pkill -INT wf-recorder"; };
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
