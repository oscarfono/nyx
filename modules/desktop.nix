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

  # Minimal display manager. Keeps the boot path small and avoids dragging
  # in a full desktop environment's session machinery.
  services.greetd = {
    enable = true;
    settings.default_session = {
      # tuigreet is a top-level package now, not an attribute of greetd.
      command = "${lib.getExe pkgs.tuigreet} --time --remember --cmd 'uwsm start hyprland-uwsm.desktop'";
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
