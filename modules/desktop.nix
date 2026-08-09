{ config, pkgs, lib, ... }:

let
  t = import ../lib/melancholy.nix;
in

# Nyx desktop, system side.
#
# This is ours. Not a wrapper around omarchy-nix or omanix. Where those
# projects solved something well we take the idea, not the dependency:
# a Hyprland session started through uwsm, a themed bar, a launcher, and
# a capture pipeline, all declared as Nix rather than shipped as scripts.

{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  # ---------------------------------------------------------------------
  # Boot: graphical, quiet, no wall of text
  # ---------------------------------------------------------------------
  # systemd in initrd (set in security.nix) is what lets Plymouth draw the
  # LUKS passphrase prompt instead of a bare console line.
  boot.plymouth = {
    enable = true;
    theme = "breeze";           # dark, understated, ships with plymouth
  };

  # Hide kernel and systemd chatter. `quiet` and udev.log_level do the work;
  # rd.systemd.show_status covers the initrd half, which is where the LUKS
  # prompt lives.
  boot.kernelParams = [
    "quiet"
    "splash"
    "loglevel=3"
    "udev.log_level=3"
    "rd.udev.log_level=3"
    "vt.global_cursor_default=0"
    "boot.shell_on_fail"        # keep an escape hatch when something breaks
  ];
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  boot.loader.timeout = 0;      # hold SPACE at boot to get the menu back

  # ---------------------------------------------------------------------
  # Greeter
  # ---------------------------------------------------------------------
  # ReGreet, not tuigreet. tuigreet is a terminal UI: fine, fast, and always
  # going to look like a terminal. ReGreet is a real GTK4 greeter, so it
  # takes our GTK theme, our icon theme, our cursor and a wallpaper, and the
  # login screen finally matches the desktop behind it.
  #
  # (GTK4 rather than GTK3 — ReGreet is built on GTK4/libadwaita. GTK3 would
  # mean an older greeter with less consistent theming, not a better one.)
  #
  # services.displayManager.regreet configures services.greetd itself, including running
  # under cage, so we do not declare default_session here.
  services.greetd.enable = true;

  services.displayManager.regreet = {
    enable = true;

    # Theme, cursor, icons and font are FIRST-CLASS OPTIONS on this module.
    # It writes them into settings.GTK itself, so setting settings.GTK by
    # hand produces a conflicting definition rather than an override.
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    cursorTheme = {
      name = "Bibata-Modern-Ice";
      package = pkgs.bibata-cursors;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    font = {
      name = "Raleway";
      package = pkgs.raleway;
      size = 12;
    };

    settings = {
      # Same wallpaper as the desktop, so login and session are continuous.
      background = {
        path = ../assets/wallpapers/melancholy-dusk.png;
        fit = "Cover";
      };
      commands = {
        reboot = [ "systemctl" "reboot" ];
        poweroff = [ "systemctl" "poweroff" ];
      };
      appearance.greeting_msg = "Not Your X";
    };

    # Melancholy, applied to the greeter's own widgets.
    extraCss = ''
      window, .background {
        background-color: ${t.bg};
      }
      entry {
        background-color: ${t.bgSubtle};
        color: ${t.fg};
        border: 2px solid ${t.amber};
        border-radius: 6px;
        padding: 8px;
      }
      entry:focus {
        border-color: ${t.cyan};
      }
      button {
        background-image: none;
        background-color: ${t.bgSubtle};
        color: ${t.fg};
        border: 1px solid ${t.fgMuted};
        border-radius: 6px;
      }
      button:hover {
        border-color: ${t.amber};
        color: ${t.amber};
      }
      label {
        color: ${t.fg};
      }
      #clock, .clock {
        color: ${t.cyan};
        font-size: 22px;
      }
    '';
  };

  # ---------------------------------------------------------------------
  # Mobile broadband (WWAN)
  # ---------------------------------------------------------------------
  # The T490 has an M.2 WWAN slot and a SIM tray, but the modem card is a
  # build-time option and many units ship without it. Harmless if absent:
  # ModemManager simply finds no device. See SUMMARY.md for how to check.
  networking.networkmanager.plugins = with pkgs; [
    networkmanager-fortisslvpn
    networkmanager-openvpn
  ];
  services.udev.packages = [ pkgs.modemmanager ];

  # Audio
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Portals, so screen sharing and file pickers work under Wayland.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "hyprland" "gtk" ];
  };

  environment.systemPackages = with pkgs; [
    # Shell of the desktop
    waybar
    fuzzel            # launcher. Smaller and saner than Walker for our needs.
    mako
    hyprlock
    hypridle
    hyprpaper
    swayosd           # volume and brightness OSD

    # Capture. The pipeline Omarchy gets right and worth copying.
    grim
    slurp
    satty             # annotate screenshots
    wf-recorder
    wl-clipboard
    cliphist

    # Controls
    brightnessctl
    playerctl
    pavucontrol
    networkmanagerapplet

    # Sharing. LocalSend is the AirDrop-alike: LAN only, no account.
    localsend

    modemmanager
    modem-manager-gui
    libmbim
    libqmi
    mobile-broadband-provider-info

    # Cursor and icons. See home/theme.nix for which are selected.
    bibata-cursors
    phinger-cursors
    papirus-icon-theme
    tela-icon-theme

    # Files and viewers
    nautilus
    imv
    mpv
    ghostty
  ];

  # LocalSend listens on 53317 to receive. Opened deliberately and narrowly;
  # everything else in modules/security.nix stays shut.
  networking.firewall = {
    allowedTCPPorts = [ 53317 ];
    allowedUDPPorts = [ 53317 ];
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
  };
}
