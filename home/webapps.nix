{ config, pkgs, lib, ... }:

# Renders lib/webapps.nix into desktop entries. Each becomes a launcher item
# indistinguishable from a native application.
#
# Brave's --app mode drops the tab strip, address bar and menu, and gives the
# window its own WM class so window rules in home/desktop.nix can target it.

let
  apps = import ../lib/webapps.nix;

  # Shared with lib/menu.nix. Read that file before you change the quoting.
  command = import ../lib/webapp-command.nix;

  mkDesktop = key: app: {
    name = "nyx-webapp-${key}";
    value = {
      name = app.name;
      exec = command app;
      icon = app.icon or "brave-browser";
      categories = app.categories or [ "Network" ];
      terminal = false;
      settings.StartupWMClass = app.class;
    };
  };
in
{
  xdg.desktopEntries = lib.mapAttrs' mkDesktop apps;
}
