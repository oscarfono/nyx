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

  # nyx-backup: one command for every interaction with the repository, so
  # the sudo + source-the-env dance lives in exactly one place.
  #
  # There is no "full vs incremental" distinction to make: restic dedupes at
  # block level, so the first snapshot is large and every one after it sends
  # only changed blocks. Each snapshot is independently restorable either
  # way. The only special case is a repository that has never been
  # initialised, which this handles.
  environment.systemPackages = [
    pkgs.restic
    (pkgs.writeShellScriptBin "nyx-backup" ''
      set -eu

      if [ "$(id -u)" -ne 0 ]; then
        exec sudo "$0" "$@"
      fi

      set -a
      . /run/secrets/restic-s3-env
      set +a

      REPO="${repository}"
      PW=/run/secrets/restic-password
      R="${pkgs.restic}/bin/restic -r $REPO --password-file $PW"

      case "''${1:-run}" in
        run)
          if ! $R cat config >/dev/null 2>&1; then
            echo "Repository not initialised. Creating it..."
            $R init
          fi
          systemctl start restic-backups-${hostName}.service
          echo
          $R snapshots --latest 1
          ;;
        snapshots) $R snapshots ;;
        stats)     $R stats latest ;;
        check)     $R check --read-data-subset=5% ;;
        mount)
          mkdir -p /mnt/restic
          echo "Browsing snapshots at /mnt/restic. Ctrl-C to unmount."
          $R mount /mnt/restic
          ;;
        restore)
          [ -n "''${2:-}" ] || { echo "usage: nyx-backup restore <target-dir> [path]" >&2; exit 1; }
          if [ -n "''${3:-}" ]; then
            $R restore latest --target "$2" --include "$3"
          else
            $R restore latest --target "$2"
          fi
          ;;
        forget)    $R forget --prune --keep-daily 7 --keep-weekly 5 --keep-monthly 12 ;;
        *)
          cat >&2 <<USAGE
usage: nyx-backup <command>

  run                       back up now (initialises the repo if needed)
  snapshots                 list every snapshot
  stats                     size of the latest snapshot
  check                     verify repository integrity (samples 5% of data)
  mount                     browse snapshots as a filesystem at /mnt/restic
  restore DIR [PATH]        restore latest snapshot into DIR
  forget                    apply the retention policy and prune

Repository: $REPO
USAGE
          exit 1
          ;;
      esac
    '')
  ];
}
