{ config, pkgs, ... }:

# The laptop copy of the LUNA memory, and the sync of the shared org-roam
# graph. See "Long-term memory" in luna/LUNA.org.
#
# The memory hub is on the VPS, and the VPS disk is not encrypted. The beta
# disk is LUKS-encrypted, so this clone is the encrypted backup.
#
# Emacs uses roam/ in this clone as org-roam-directory. Coops and LUNA share
# the notes in roam/. Every 10 minutes the timer:
#   1. commits the changes in roam/ (the notes of Coops),
#   2. pulls the hub with rebase (the notes of LUNA),
#   3. pushes to the hub.
# The timer commits roam/ only. Commit a change to another file by hand.
#
# The timer cannot answer the GPG prompt, so its commits are not signed.
# This applies to the timer only, not to a commit that Coops makes.
#
# CAUTION: if Coops and LUNA change the end of one note in the same 10
# minutes, the rebase can stop with a conflict. The timer then stops, keeps
# all the text, and sends a desktop notice. Resolve the conflict in magit.
#
# Make the clone once:
#
#   git clone coops@luna:/var/lib/luna/memory.git ~/org/luna
#
# Until the clone exists, the service does nothing.

let
  clone = "${config.home.homeDirectory}/org/luna";
  git = "${pkgs.git}/bin/git -C ${clone}";
in
{
  systemd.user.services.luna-memory-sync = {
    Unit.Description = "Sync the LUNA memory and the shared org-roam notes with the hub";
    Service = {
      Type = "oneshot";
      # A user service has a minimal PATH, and git needs ssh for the pull.
      Environment = [ "GIT_SSH_COMMAND=${pkgs.openssh}/bin/ssh -o BatchMode=yes" ];
      ExecStart = toString (pkgs.writeShellScript "luna-memory-sync" ''
        set -eu
        if [ ! -d "${clone}/.git" ]; then
          echo "No clone at ${clone}. Nothing to do."
          exit 0
        fi

        stop() {
          ${pkgs.libnotify}/bin/notify-send -u critical -a LUNA "Memory sync stopped" "$1"
          exit 1
        }

        # A rebase that stopped before: do not start another one.
        if [ -d "${clone}/.git/rebase-merge" ] || [ -d "${clone}/.git/rebase-apply" ]; then
          stop "A rebase waits in ~/org/luna. Resolve it in magit."
        fi

        if [ -d "${clone}/roam" ]; then
          ${git} add -A -- roam
          if ! ${git} diff --cached --quiet; then
            ${git} -c commit.gpgsign=false commit --quiet -m "Coops: roam notes from beta"
          fi
        fi

        # --autostash keeps a change to another file that is not committed.
        ${git} pull --rebase --autostash --quiet || stop "The pull stopped with a conflict. Resolve it in magit."
        ${git} push --quiet origin HEAD:main || stop "The push to the hub failed. Run: systemctl --user status luna-memory-sync"
      '');
    };
  };

  systemd.user.timers.luna-memory-sync = {
    Unit.Description = "Sync the LUNA memory every 10 minutes";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "10m";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
