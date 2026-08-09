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

  environment.systemPackages = with pkgs; [
    mangohud
    protonup-qt
  ];
}
