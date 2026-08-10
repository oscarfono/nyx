{ config, pkgs, lib, ... }:

# An escape hatch for things that are yours rather than Nyx's.
#
# Anything in ~/.config/zsh/local/*.zsh is sourced at shell start. Nix
# creates the directory and sources whatever is in it; the contents are not
# managed, not in this repo, and not published.
#
# Why not a gitignored .nix file: flakes read the git INDEX, so a file git
# does not track is invisible to Nix. A gitignored module cannot be
# imported. This directory sidesteps that entirely.
#
# The trade is deliberate. These files are NOT reproducible: a fresh machine
# gets an empty directory. If a function matters enough to survive a
# reinstall, it belongs either in this repo (if it is general) or in a
# private flake input (if it is not) — see the note at the bottom.

{
  systemd.user.tmpfiles.rules = [
    "d %h/.config/zsh/local 0700 - - -"
  ];

  programs.zsh.initContent = lib.mkOrder 1550 ''
    # Personal, per-project shell functions. Not managed by Nix.
    # Drop a .zsh file in here and open a new shell; no rebuild needed.
    if [ -d "$HOME/.config/zsh/local" ]; then
      for f in "$HOME/.config/zsh/local"/*.zsh(N); do
        source "$f"
      done
    fi
  '';

  # A private flake input is the reproducible version of this:
  #
  #   inputs.nyx-private.url = "git+ssh://git@github.com/oscarfono/nyx-private";
  #   ...
  #   homeModules = [ ./home inputs.nyx-private.homeManagerModules.default ];
  #
  # That gets the functions onto a new machine with the rest of the config,
  # at the cost of needing an SSH key present before the first build — which
  # on a fresh install is exactly when you do not have one yet. Worth it for
  # things you would miss; overkill for a build shortcut.
}
