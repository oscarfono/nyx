{ config, pkgs, lib, ... }:

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

  # Minimal display manager. Keeps the boot path small and avoids dragging
  # in a full desktop environment's session machinery.
  services.greetd = {
    enable = true;
    settings.default_session = {
      # tuigreet is a top-level package now, not an attribute of greetd.
      # tuigreet, themed to melancholy. Colours are limited to the ANSI
      # names it accepts, so amber maps to yellow and the muted greys to
      # the bright/normal black pair.
      command = lib.concatStringsSep " " [
        "${lib.getExe pkgs.tuigreet}"
        "--time --time-format '%H:%M  %a %d %b'"
        "--remember --remember-session"
        "--asterisks"
        "--greeting 'Not Your X'"
        "--window-padding 2"
        "--theme 'border=yellow;text=white;prompt=yellow;time=cyan;action=white;button=yellow;container=black;input=white'"
        "--cmd 'uwsm start hyprland-uwsm.desktop'"
      ];
      user = "greeter";
    };
  };

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
