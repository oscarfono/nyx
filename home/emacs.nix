{ config, pkgs, lib, ... }:

# Emacs, user side. Add to home/default.nix (already imported).
#
# straight.el needs ~/.emacs.d to be WRITABLE: it clones into
# straight/repos and byte-compiles into straight/build. That rules out a Nix
# store symlink, so the config repo stays a normal git clone and Nix stays
# out of its way.
#
# Reproducibility does not disappear, it moves: commit
# ~/.emacs.d/straight/versions/default.el to your config repo. That plus
# straight-thaw-versions is straight's flake.lock. Freeze with
# M-x straight-freeze-versions before rebuilding a machine.
#
# IMPORTANT: the bootstrap below is a user SERVICE, not an activation script.
# Activation runs during home-manager-<user>.service, which starts before the
# network is up, and a failed clone there aborts the ENTIRE activation, so no
# Hyprland config, no shell, nothing. Ask me how I know. As a service it
# waits for the network and fails harmlessly on its own if it cannot reach
# GitHub.

let
  straightRev = "adb0fb37bc5fc298f5ed9f61447cfe379fff77ed";  # develop @ 2026-08-08
in
{
  systemd.user.services.nyx-emacs-bootstrap = {
    Unit = {
      Description = "Clone .emacs.d and seed straight.el";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = toString (pkgs.writeShellScript "nyx-emacs-bootstrap" ''
        set -u
        GIT=${pkgs.git}/bin/git

        if [ ! -d "$HOME/.emacs.d/.git" ]; then
          $GIT clone https://github.com/oscarfono/.emacs.d.git "$HOME/.emacs.d" \
            || echo "nyx: .emacs.d clone failed, will retry next boot" >&2
        fi

        # Seed straight.el at a pinned revision so the url-retrieve of
        # install.el in your early-init.el never runs. That block is the
        # elisp equivalent of curl | bash and this removes it without you
        # having to edit early-init.el at all.
        STRAIGHT_REPO="$HOME/.emacs.d/straight/repos/straight.el"
        if [ -d "$HOME/.emacs.d" ] && [ ! -d "$STRAIGHT_REPO/.git" ]; then
          $GIT clone https://github.com/radian-software/straight.el "$STRAIGHT_REPO" \
            && $GIT -C "$STRAIGHT_REPO" checkout ${straightRev} \
            || echo "nyx: straight.el seed failed, early-init will bootstrap it" >&2
        fi

        exit 0
      '');
    };

    Install.WantedBy = [ "default.target" ];
  };

  # The Emacs daemon starts at graphical login. On a fresh machine that can
  # be before the bootstrap above has finished cloning, which gives you a
  # daemon running with no config until the next restart. Order it.
  #
  # services.emacs with startWithGraphical already sets the unit type and
  # install target. Adding our own Install.WantedBy / PartOf / Restart on
  # top of that made systemd reject the unit outright (BadUnitSetting), so
  # this override does only the two things the module does not:
  # ordering after the bootstrap, and a Wayland environment.
  systemd.user.services.emacs = {
    Unit.After = [ "nyx-emacs-bootstrap.service" ];
    Unit.Wants = [ "nyx-emacs-bootstrap.service" ];

    # The daemon inherits the systemd user environment, which does not
    # include the Wayland session by default. Without these it starts
    # headless or falls back to XWayland, and emacsclient -c gives you a
    # frame that cannot properly open files.
    Service.Environment = [
      "GDK_BACKEND=wayland"
      "XDG_SESSION_TYPE=wayland"
      "EGL_PLATFORM=wayland"
    ];
  };
}
