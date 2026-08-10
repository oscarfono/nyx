{ config, pkgs, lib, ... }:

# bat, themed with melancholy. Home-manager module.
#
# The .tmTheme is generated from lib/melancholy.nix's palette, so bat agrees
# with the terminal, the bar and Emacs. It lives in assets/ as a committed
# file rather than being generated at build time, because tmTheme is XML and
# generating it from Nix would be unreadable.
#
# Import from home/default.nix. Requires assets/melancholy.tmTheme.

{
  programs.bat = {
    enable = true;

    themes.melancholy = {
      src = ../assets;
      file = "melancholy.tmTheme";
    };

    config = {
      theme = "melancholy";
      style = "numbers,changes,header";
      pager = "less -FR";
    };

    extraPackages = with pkgs.bat-extras; [
      batdiff
      batgrep
      batman        # man pages through bat
    ];
  };

  # delta uses bat's syntax themes, so git diffs match too.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      syntax-theme = "melancholy";
      line-numbers = true;
      navigate = true;
    };
  };
}
