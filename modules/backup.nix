{ config, pkgs, lib, username, hostName, ... }:

# Backups with restic. NOT imported by default: see the checklist below.
#
# What this protects: the things that are not in git and cannot be rebuilt.
# The Nix store is not backed up because the flake reproduces it.
#
# BEFORE IMPORTING THIS MODULE:
#   1. Choose a repository and put it in `repository` below.
#        local disk:  /run/media/${username}/backup/restic
#        over ssh:    sftp:user@host:/srv/restic
#        B2:          b2:bucket-name:path
#   2. Add a password to the secrets file:
#        openssl rand -base64 32          # generate one, keep a copy OFFLINE
#        sops secrets/secrets.yaml        # add:  restic-password: <that value>
#   3. Import from hosts/<host>/default.nix and rebuild.
#   4. Initialise the repo once:
#        sudo restic -r <repository> --password-file /run/secrets/restic-password init
#
# Losing the password means losing the backups. Restic cannot recover it.

let
  # S3-compatible object storage. See SUMMARY.md for the jurisdiction note.
  # Format: s3:https://<endpoint>/<bucket>
  repository = "s3:https://sos-ch-gva-2.exo.io/beta-backup-bucket";
in
{
  sops.secrets.restic-password = { };

  # S3 credentials. Add to secrets.yaml alongside restic-password:
  #   restic-s3-env: |
  #     AWS_ACCESS_KEY_ID=...
  #     AWS_SECRET_ACCESS_KEY=...
  sops.secrets.restic-s3-env = { };

  services.restic.backups.${hostName} = {
    inherit repository;
    passwordFile = config.sops.secrets.restic-password.path;
    environmentFile = config.sops.secrets.restic-s3-env.path;
    initialize = false;   # deliberate: init by hand so a typo'd path does
                          # not silently create a second empty repo

    paths = [
      "/home/${username}/.shh"          # authinfo.gpg and friends
      "/home/${username}/.ssh"
      "/home/${username}/.gnupg"
      "/home/${username}/.emacs.d"      # includes straight/versions lockfile
      "/home/${username}/Documents"
      "/home/${username}/Projects"
      "/home/${username}/Pictures"
    ];

    exclude = [
      "**/.git"                 # remotes have these
      "**/node_modules"
      "**/target"
      "**/result"
      "**/.direnv"
      "/home/${username}/.emacs.d/straight/build"
      "/home/${username}/.emacs.d/eln-cache"
    ];

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;        # runs on next boot if the machine was off
      RandomizedDelaySec = "30m";
    };

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];
  };

  environment.systemPackages = [ pkgs.restic ];
}
