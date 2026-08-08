{ config, pkgs, lib, ... }:

# Emacs, system side.
#
# Division of labour, given you run straight.el:
#   Nix      : the Emacs binary, native-comp toolchain, and every system
#              binary Emacs or your packages shell out to
#   straight : all elisp, including melancholy-theme
#
# Nothing is listed in emacsWithPackages. Two package managers on one
# load-path is the failure mode this whole project exists to avoid.
#
# melancholy-theme goes in your config, not here. One line, since it is your
# repo and straight is already bootstrapped by the time init.el runs:
#
#   (use-package melancholy-theme
#     :straight (:host github :repo "oscarfono/melancholy-theme")
#     :config (load-theme 'melancholy t))
#
# NOTE: delete the emacs30-pgtk entry, the services.emacs block and the
# EDITOR/VISUAL variables from modules/apps.nix, or the rebuild fails on
# duplicate option definitions.

let
  emacsPkg = pkgs.emacs30-pgtk;
in
{
  environment.systemPackages = [
    emacsPkg

    # straight clones and byte-compiles at runtime, so the toolchain has to
    # be present on the system, not just at build time.
    pkgs.git
    pkgs.gnutls          # url-retrieve over https, and straight's fetches
    pkgs.gcc
    pkgs.libgccjit       # native-comp
    pkgs.gnumake
    pkgs.cmake           # vterm, if your config uses it
    pkgs.libtool

    # Things your config reaches for.
    pkgs.ripgrep
    pkgs.fd
    pkgs.imagemagick
    pkgs.sqlite
    pkgs.texliveSmall    # org to PDF
    pkgs.aspell
    pkgs.aspellDicts.en
    pkgs.aspellDicts.en_AU

    # early-init.el sets auth-sources to a .gpg file, so gpg must be present
    # before the first frame. pinentry is configured in modules/devops.nix.
    pkgs.gnupg
  ];

  services.emacs = {
    enable = true;
    package = emacsPkg;
    defaultEditor = true;
    startWithGraphical = true;
  };

  environment.variables = {
    EDITOR = "emacsclient -c -a 'emacs'";
    VISUAL = "emacsclient -c -a 'emacs'";
  };
}
