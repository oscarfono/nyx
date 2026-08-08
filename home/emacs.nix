{ config, pkgs, lib, ... }:

# Emacs, user side. Add to home/default.nix.
#
# Your repo already ships early-init.el, so Nix does NOT write one. It only
# does two things here: clone the config if absent, and seed straight.el at a
# pinned revision so the bootstrap block in your early-init.el never has to
# fetch and eval install.el over the network.

let
  # Pin this. Bump it deliberately, the way you would bump flake.lock.
  straightRev = "2f3ff3d2f3e5b1eb5b13d0b6a1e2fcdb37c26e0e";  # REPLACE with a real commit
in
{
  # 1. Clone the config if it is not there. Idempotent.
  home.activation.cloneEmacsConfig =
    config.lib.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -d "$HOME/.emacs.d/.git" ]; then
        $DRY_RUN_CMD ${pkgs.git}/bin/git clone \
          https://github.com/oscarfono/.emacs.d.git "$HOME/.emacs.d"
      fi
    '';

  # 2. Seed straight.el itself at a pinned revision.
  #
  # Your early-init.el currently does this instead:
  #
  #   (url-retrieve-synchronously ".../develop/install.el") -> eval-print-last-sexp
  #
  # That fetches whatever is on the develop branch at that moment and evaluates
  # it. It is the elisp equivalent of curl | bash, and it is the single largest
  # piece of unpinned remote code execution left in the build. Seeding the repo
  # here means bootstrap-file already exists, so that branch of your `unless`
  # never runs, and you did not have to edit early-init.el at all.
  #
  # This clones a real git repo rather than copying from the Nix store, because
  # straight manages itself with git and straight-freeze-versions needs .git to
  # be present.
  home.activation.seedStraight =
    config.lib.dag.entryAfter [ "cloneEmacsConfig" ] ''
      STRAIGHT_REPO="$HOME/.emacs.d/straight/repos/straight.el"
      if [ ! -d "$STRAIGHT_REPO/.git" ]; then
        $DRY_RUN_CMD ${pkgs.git}/bin/git clone \
          https://github.com/radian-software/straight.el "$STRAIGHT_REPO"
        $DRY_RUN_CMD ${pkgs.git}/bin/git -C "$STRAIGHT_REPO" checkout ${straightRev}
      fi
    '';

  # 3. Reproducibility for elisp lives in straight's lockfile, not in Nix.
  #    Commit ~/.emacs.d/straight/versions/default.el to your config repo.
  #    M-x straight-freeze-versions before rebuilding a machine,
  #    M-x straight-thaw-versions on the new one.
  #    Without that file, a fresh T490s gets today's HEAD of every package,
  #    which is not the same config you are running now.
}
