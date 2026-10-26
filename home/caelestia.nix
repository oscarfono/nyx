{ config, pkgs, lib, inputs, ... }:

let
  t = import ../lib/melancholy.nix;

  # lib/melancholy.nix, rendered into a caelestia scheme. See that file for
  # the mapping from the 16 melancholy colours to the 110 caelestia keys.
  melancholyText = (import ../lib/caelestia-scheme.nix { inherit lib; }).text;

  melancholyFile = pkgs.writeText "melancholy-dark.txt" melancholyText;

  # caelestia reads a scheme ONLY from <cli>/data/schemes, and caelestia
  # reads no directory under $HOME. So the scheme goes into the package.
  # `caelestia scheme set -n` then offers melancholy, because the choices
  # for that flag come from a listing of that directory at run time.
  #
  # melancholy is a dark theme and melancholy has no light variant. The
  # light file holds the dark colours, so a press of Light in the launcher
  # changes nothing instead of failing.
  caelestia-cli-melancholy = pkgs.caelestia-cli.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      for d in $out/lib/python*/site-packages/caelestia/data/schemes; do
        mkdir -p "$d/melancholy/default"
        cp ${melancholyFile} "$d/melancholy/default/dark.txt"
        cp ${melancholyFile} "$d/melancholy/default/light.txt"
      done
    '';
  });

  # The seeded copy in the library, and not the store path. The picker in
  # nyx-wallpaper lists the library, so a wallpaper from the library stays
  # consistent with `nyx-wallpaper current`. home/wallpaper.nix seeds the
  # file, so the file is always present.
  defaultWallpaper = "${config.home.homeDirectory}/Pictures/wallpapers/dark-abstract.png";
in

# Caelestia, a Quickshell desktop shell.
#
# Quickshell is a QtQuick toolkit for desktop components. One long-lived
# process draws the bar, the launcher, the notifications, the OSD, the
# dashboard and the panels. The panels are the reason to want it: a Waybar
# module shows a value and runs a command, but a Quickshell panel is a real
# window. So the audio panel holds a slider for each application, and the
# network panel scans for wifi.
#
# Quickshell speaks to each service through a typed QML module, and not
# through a shell script. The modules are Pipewire, Networking, Bluetooth,
# UPower, Mpris, Notifications, SystemTray, Pam, Polkit and Hyprland.
#
# This file replaces 2 programs. See the notes in home/desktop.nix:
#   waybar  the bar, and the StatusNotifierWatcher for the tray
#   mako    the notification daemon
#
# These programs stay, and the notes below say why:
#   hyprlock   the lock screen
#   swaybg     the wallpaper, with nyx-wallpaper
#   fuzzel     the launcher, on SUPER+Space
#   walker     the menus, from lib/menu.nix

{
  imports = [ inputs.caelestia.homeManagerModules.default ];

  programs.caelestia = {
    enable = true;

    # The nixpkgs build, and NOT the build from the caelestia flake.
    #
    # The flake builds quickshell from a git checkout with clang, and the
    # binary cache holds no such build. So the flake package compiles Qt
    # and quickshell from source, which takes hours on this machine. The
    # nixpkgs build is in the cache, and the nixpkgs build carries
    # quickshell 0.3.2, the fonts and the tools in one closure.
    #
    # The closure is 1.8GB. That is the price of a Qt application.
    package = pkgs.caelestia-shell;

    # The shell calls the CLI for some actions. `caelestia scheme set`
    # changes the colour scheme, and the Light and Dark entries in the
    # launcher call that command.
    cli = {
      enable = true;
      package = caelestia-cli-melancholy;
    };

    # A user service, so the shell starts with the session and stops with
    # the session. The module restarts the service when the settings below
    # change, through X-Restart-Triggers.
    systemd.enable = true;

    # The module writes these settings to ~/.config/caelestia/shell.json.
    settings = {
      services = {
        # DARK MODE.
        #
        # smartScheme reads the wallpaper and derives the mode and the
        # variant from the wallpaper. The default is true. So a bright
        # wallpaper gives a light shell, and `nyx-wallpaper next` cycles
        # through 4 wallpapers of which some are bright.
        #
        # false keeps the mode fixed. The shell starts in dark mode,
        # because the shell reads the mode from
        # ~/.local/state/caelestia/scheme.json and that file does not exist
        # until something writes the file. The fallback is dark.
        #
        # To set the mode by hand at any time:
        #   caelestia scheme set -m dark
        #   caelestia scheme set -m light
        smartScheme = false;

        # clockFormat is an ENUM, and not a format string. The 3 values are
        # Auto, TwelveHour and TwentyFourHour. A format string gives this
        # warning in the log, and the shell keeps the default:
        #   Error decoding option services.clockFormat:
        #   Invalid enum value <string>. Expected one of Auto, TwelveHour,
        #   TwentyFourHour
        clockFormat = "TwentyFourHour";
      };

      general = {
        # The applications caelestia starts for itself. The defaults are
        # foot, pwvucontrol, mpv and thunar, and this machine has none of
        # foot, pwvucontrol or thunar.
        apps = {
          terminal = [ "ghostty" ];
          audio = [ "pavucontrol" ];
          playback = [ "mpv" ];
          explorer = [ "nautilus" ];
        };

        # THE IDLE TIMERS STAY WITH HYPRIDLE, so this list is empty.
        #
        # caelestia carries its own idle timers, and the timers are ON by
        # default: lock at 180s, dpms off at 300s, suspendThenHibernate at
        # 600s. hypridle already runs dim at 240s, lock at 300s, dpms off
        # at 360s and suspend at 900s.
        #
        # Both sets of timers would run. So the screen would lock at 180s
        # AND at 300s, and the machine would suspend at 600s AND at 900s.
        # An empty list stops the caelestia timers.
        #
        # hypridle keeps the timers for a second reason: nyx-caffeine,
        # nyx-claude-unattended, the menu entry for the idle lock and
        # nyx-doctor all read or stop the hypridle unit. A move to
        # caelestia has to change all 4 at the same time. See
        # modules/power.nix for the suspend watchdog, which is independent
        # of this choice and works either way.
        idle.timeouts = [ ];
      };

      # The OSD shows the volume and the brightness. swayosd is off now,
      # see home/desktop.nix. caelestia reads Pipewire and the backlight
      # directly, so the OSD appears whatever changes the value.
      osd = {
        enabled = true;
        enableBrightness = true;
        enableMicrophone = true;
      };

      # The lock screen is LOADED, and the lock screen is NOT the session
      # lock yet. This state is for a test, and the test needs you present.
      #
      # hypridle still calls hyprlock for `lock_cmd`, and SUPER+SHIFT+L
      # still calls `loginctl lock-session`, which reaches hyprlock. So
      # nothing reaches the caelestia lock screen on its own. Only the IPC
      # command reaches the caelestia lock screen:
      #
      #   caelestia shell lock lock      show the lock screen
      #   caelestia shell lock isLocked  report the state
      #
      # WARNING: read this before the test. A lock screen uses the
      # ext-session-lock protocol. The compositor keeps the session locked
      # when the lock client dies, because an unlocked screen after a crash
      # is a security fault. So `pkill quickshell` does NOT unlock the
      # screen, and a dead lock client can lock you out of the session.
      #
      # Test like this:
      #   1. Commit and push first, so a reboot costs nothing.
      #   2. Keep a TTY ready: CTRL+ALT+F2 reaches a text login.
      #   3. Run `caelestia shell lock lock`.
      #   4. Type the password and confirm the unlock.
      #
      # After a good test, hypridle `lock_cmd` and the SUPER+SHIFT+L bind
      # move to the caelestia lock screen, and hyprlock goes.
      lock = {
        enabled = true;

        # Neither one is set up on this machine, and each one adds a try
        # and a delay before the password prompt accepts a password.
        enableFprint = false;
        enableHowdy = false;
      };

      # The bar stays on screen. The alternative hides the bar until the
      # pointer reaches the edge of the screen.
      bar.persistent = true;

      # The wallpaper library that nyx-wallpaper already seeds. The
      # caelestia default is ~/Pictures/Wallpapers, with a capital W, and
      # that directory does not exist here.
      paths.wallpaperDir = "${config.home.homeDirectory}/Pictures/wallpapers";
    };
  };

  # Selects the scheme and the wallpaper.
  #
  # Neither one is a setting in shell.json. caelestia keeps the scheme in
  # ~/.local/state/caelestia/scheme.json and the wallpaper in
  # ~/.local/state/caelestia/wallpaper/path.txt, and the CLI writes both
  # files. A read-only file from the nix store in either place would stop
  # the CLI from working, so this service writes them instead.
  #
  # The service runs at each login and corrects the scheme if the scheme
  # drifts. The service sets the wallpaper only when no wallpaper is set, so
  # `nyx-wallpaper next` keeps its choice across a login.
  systemd.user.services.nyx-caelestia-theme = {
    Unit = {
      Description = "Melancholy scheme and wallpaper for caelestia";
      After = [ "caelestia.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = toString (pkgs.writeShellScript "nyx-caelestia-theme" ''
        set -u
        CLI=${caelestia-cli-melancholy}/bin/caelestia
        STATE="$HOME/.local/state/caelestia"

        # -N keeps the mode fixed. Without -N the CLI reads the wallpaper
        # and changes the mode, which is the smartScheme behaviour that
        # shell.json turns off.
        if [ ! -s "$STATE/wallpaper/path.txt" ]; then
          $CLI wallpaper -f ${defaultWallpaper} -N \
            || echo "nyx: could not set the caelestia wallpaper" >&2
        fi

        if ! ${pkgs.gnugrep}/bin/grep -q '"name": *"melancholy"' "$STATE/scheme.json" 2>/dev/null; then
          $CLI scheme set -n melancholy -f default -m dark \
            || echo "nyx: could not set the melancholy scheme" >&2
        fi

        exit 0
      '');
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
