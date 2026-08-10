{ config, pkgs, lib, ... }:

# Steam and Linux gaming. Import from hosts/t490s/default.nix.
# Note: T490s is Intel integrated graphics. Expect indie and older titles,
# not current AAA.

{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = false;      # flip if you use Remote Play
    dedicatedServer.openFirewall = false;
    protontricks.enable = true;
  };

  programs.gamemode.enable = true;

  # NOTE: the unfree allow-list lives in modules/apps.nix and nowhere else.
  # nixpkgs.config.allowUnfreePredicate is a single function, so a second
  # definition here does not merge with that one, it replaces it, and
  # whichever loses silently stops allowing its own packages. Steam's names
  # are in that one list.

  hardware.graphics.enable32Bit = true;

  # Steam's UI is Chromium-based and does its own scaling. With
  # force_zero_scaling it renders at native resolution, so it needs telling
  # the display scale or the UI comes out tiny.
  environment.sessionVariables.STEAM_FORCE_DESKTOPUI_SCALING = "1.5";

  environment.systemPackages = with pkgs; [
    mangohud
    protonup-qt
  ];
}
