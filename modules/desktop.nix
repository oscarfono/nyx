{ config, pkgs, lib, ... }:

# The Omarchy-shaped part: Hyprland plus the supporting cast, declared
# properly rather than curl-piped into place.

{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  # Minimal display manager. tuigreet keeps the boot path small and avoids
  # dragging in a full DE's worth of session machinery.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd 'uwsm start hyprland-uwsm.desktop'";
      user = "greeter";
    };
  };

  # Audio.
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
    waybar
    wofi
    mako
    hyprlock
    hypridle
    hyprpaper
    grim
    slurp
    wl-clipboard
    cliphist
    brightnessctl
    playerctl
    pavucontrol
    nautilus
    alacritty
    imv
    mpv
  ];

  fonts = {
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
      noto-fonts
      noto-fonts-emoji
      liberation_ttf
    ];
    fontconfig.defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font" ];
      sansSerif = [ "Noto Sans" ];
      serif = [ "Noto Serif" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  # No Google fonts pulled from the network at runtime, no telemetry-laden
  # font services. Everything above is in the store, offline, pinned.

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
  };
}
