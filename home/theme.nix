{ config, pkgs, lib, ... }:

# Dark everywhere, cursors and icons.
#
# Three separate toolkits need telling independently, and an app that misses
# one of them is the one that blinds you with a white window at 11pm:
#   GTK3/4  gtk.* below, plus the gtk-application-prefer-dark-theme flag
#   libadwaita  ignores the theme and follows the dconf colour-scheme only
#   Qt      qt.* below, pointed at the GTK theme so it follows along

let
  t = import ../lib/melancholy.nix;

  # Bibata Modern Ice: white outline, dark fill, reads well on a dark
  # desktop without the cartoonish weight of Breeze. Alternatives worth a
  # look if it does not suit: phinger-cursors-light (softer, larger),
  # or Bibata-Modern-Classic (black fill).
  cursorTheme = "Bibata-Modern-Ice";
  cursorPackage = pkgs.bibata-cursors;
  cursorSize = 24;
in
{
  # -------------------------------------------------------------------
  # Cursor
  # -------------------------------------------------------------------
  # home.pointerCursor sets it for GTK, X11 and the XCURSOR_* environment
  # in one place, which is what Hyprland and every toolkit actually read.
  home.pointerCursor = {
    enable = true;
    name = cursorTheme;
    package = cursorPackage;
    size = cursorSize;
    gtk.enable = true;
  };

  # -------------------------------------------------------------------
  # GTK
  # -------------------------------------------------------------------
  gtk = {
    enable = true;

    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };

    # Papirus-Dark with amber folders, which is as close to the melancholy
    # accent as a stock icon theme gets. tela-icon-theme is installed too if
    # you prefer its rounder look: "Tela-dark" or "Tela-orange-dark".
    iconTheme = {
      name = "WhiteSur-dark";
      package = pkgs.whitesur-icon-theme;
    };

    font = {
      name = "Raleway";
      size = 11;
    };

    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
      gtk-cursor-theme-name = cursorTheme;
      gtk-cursor-theme-size = cursorSize;
    };

    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
  };

  # libadwaita apps (Nautilus, most modern GNOME software) ignore the GTK
  # theme entirely and read this instead. Without it they stay light no
  # matter what else is set.
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "Adwaita-dark";
    # Must match gtk.iconTheme.name above: home-manager's gtk3 module sets
    # this same dconf key, and two different values is a hard conflict.
    icon-theme = "WhiteSur-dark";
    cursor-theme = cursorTheme;
    cursor-size = cursorSize;
    font-name = "Raleway 11";
    monospace-font-name = "CommitMono Nerd Font Mono 11";
  };

  # -------------------------------------------------------------------
  # Qt
  # -------------------------------------------------------------------
  # KeePassXC is the Qt app you will actually look at, so this matters.
  qt = {
    enable = true;
    # "gtk3" is the modern native Qt plugin; plain "gtk" now means the
    # legacy qtstyleplugins path.
    platformTheme.name = "gtk3";
    style = {
      name = "adwaita-dark";
      package = pkgs.adwaita-qt;
    };
  };

  # -------------------------------------------------------------------
  # Everything else
  # -------------------------------------------------------------------
  home.sessionVariables = {
    XCURSOR_THEME = cursorTheme;
    XCURSOR_SIZE = toString cursorSize;
    # Electron and Chromium-based apps (Brave, Claude Code's UI) read this.
    GTK_THEME = "Adwaita:dark";
  };

  # Tell Brave to render its own chrome dark rather than following nothing.
  # The managed policy in modules/apps.nix handles the rest of its config.
  xdg.configFile."gtk-3.0/settings.ini".force = true;
}
