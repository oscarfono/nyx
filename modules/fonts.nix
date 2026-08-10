{ config, pkgs, lib, ... }:

# Fonts.
#
# The melancholy chain:
#   Mono     CommitMono Nerd Font Mono, then JetBrains Mono, then Hack
#   Sans     Raleway, then Inter
#   Cursive  Caveat
#
# The Nerd Font variants are patched with the glyphs Waybar, the menus and
# the shell prompt use. Plain CommitMono would render those as boxes.

{
  fonts = {
    packages = with pkgs; [
      # Mono, patched
      nerd-fonts.commit-mono
      nerd-fonts.jetbrains-mono
      nerd-fonts.hack
      nerd-fonts.symbols-only     # glyph fallback for anything unpatched

      # Mono, unpatched originals for anything that dislikes the patched
      # metrics (some PDF and print workflows do).
      commit-mono
      jetbrains-mono
      hack-font

      # Sans
      raleway
      inter

      # Cursive. google-fonts is ~2GB unfiltered, so take just this one.
      (google-fonts.override { fonts = [ "Caveat" ]; })

      # Coverage for everything else
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      liberation_ttf
    ];

    fontconfig = {
      enable = true;
      defaultFonts = {
        monospace = [ "CommitMono Nerd Font Mono" "JetBrainsMono Nerd Font" "Hack Nerd Font" ];
        sansSerif = [ "Raleway" "Inter" "Noto Sans" ];
        serif = [ "Noto Serif" "Liberation Serif" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };
}
