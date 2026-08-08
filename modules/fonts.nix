{ config, pkgs, lib, ... }:

# Fonts. melancholy specifies a preferred chain, so it is declared here
# rather than left to whatever the desktop layer happens to ship.
#   Mono    CommitMono Nerd Font Mono, falling back to JetBrains Mono, Hack
#   Sans    Raleway, falling back to Inter
#   Cursive Caveat

{
  fonts = {
    packages = with pkgs; [
      nerd-fonts.commit-mono
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
      hack-font
      raleway
      google-fonts          # carries Caveat. Large. Swap for a narrower
                            # package if closure size starts to annoy you.
      noto-fonts
      noto-fonts-emoji
      liberation_ttf
    ];

    fontconfig.defaultFonts = {
      monospace = [ "CommitMono Nerd Font Mono" "JetBrainsMono Nerd Font" "Hack" ];
      sansSerif = [ "Raleway" "Inter" "Noto Sans" ];
      serif     = [ "Noto Serif" ];
      emoji     = [ "Noto Color Emoji" ];
    };
  };
}
