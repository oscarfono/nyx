{ config, pkgs, lib, ... }:

# The dock. nwg-dock-hyprland, at the bottom edge, hidden until the pointer
# touches that edge.
#
# The dock holds a fixed list of graphical applications. It is not a task
# bar, and it holds no shell programs. SUPER opens the caelestia launcher
# for everything else.
#
# The dock matches a pin to a window by the window class. Each pin is a
# desktop ID, and the dock reads the icon and the command from that
# desktop entry. When the class of a window is equal to a pin, the dock
# shows a dot under that pin. A click on the pin then focuses the window,
# and does not start a second copy.
#
# The pins are a read-only file from the nix store. Thus "Pin" and "Unpin"
# in the right-click menu of the dock do not work. Edit `pins` below, then
# rebuild.

let
  t = import ../lib/melancholy.nix;
  craft = import ../lib/craft.nix;

  pins =
    map (name: "ai.storyteller.${name}") (builtins.attrNames craft)
    ++ [
      "gods-eye-view"
      "emacsclient"
    ];

  # The dock also shows each window that has no pin. These classes stay off
  # the dock: the terminal, and the programs that have a key on SUPER.
  #
  # Two of the classes belong to pinned programs, and the class is not
  # equal to the pin. Without these entries, each program gets a second
  # icon on the dock while it runs:
  #   emacs                      emacsclient opens a frame of the daemon
  #   brave-localhost__-Default  gods-eye-view opens a Brave app window
  #
  # A program that is not in this list shows on the dock while it runs.
  ignoredClasses = [
    "com.mitchellh.ghostty"
    "brave-browser"
    "firefox"
    "chromium-browser"
    "org.keepassxc.KeePassXC"
    "org.gnome.Nautilus"
    "qalculate-gtk"
    "emacs"
    "brave-localhost__-Default"
  ];

  args = lib.escapeShellArgs [
    "-d"                 # hide until the pointer touches the edge
    "-p" "bottom"
    "-i" "44"            # icon size in pixels
    "-mb" "6"            # gap between the dock and the edge
    "-nolauncher"        # SUPER opens the launcher, so no launcher button
    "-g" (lib.concatStringsSep " " ignoredClasses)
  ];
in
{
  home.packages = [ pkgs.nwg-dock-hyprland ];

  home.file.".cache/nwg-dock-pinned".text = lib.concatLines pins;

  xdg.configFile."nwg-dock-hyprland/style.css".text = ''
    window {
      background: alpha(${t.bg}, 0.92);
      border: 1px solid ${t.bgSubtle};
      border-radius: 14px;
    }

    #box {
      padding: 6px 10px;
    }

    button, image {
      background: none;
      border-style: none;
      box-shadow: none;
    }

    button {
      padding: 4px;
      margin: 0 3px;
      color: ${t.fg};
      border-radius: 10px;
    }

    button:hover {
      background-color: ${t.bgSubtle};
    }

    button:focus {
      box-shadow: none;
    }

    /* The window that has the focus. */
    #active {
      border-bottom: 2px solid ${t.accent};
    }
  '';

  systemd.user.services.nwg-dock = {
    Unit = {
      Description = "Dock at the bottom edge";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      # The dock reads the pins and the style only when it starts.
      X-Restart-Triggers = [
        config.home.file.".cache/nwg-dock-pinned".source
        config.xdg.configFile."nwg-dock-hyprland/style.css".source
      ];
    };
    Service = {
      ExecStart = "${pkgs.nwg-dock-hyprland}/bin/nwg-dock-hyprland ${args}";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
