{ config, pkgs, ... }:

# The laptop copy of the LUNA memory. See luna/LUNA.org.
#
# The memory hub is on the VPS, and the VPS disk is not encrypted. The beta
# disk is LUKS-encrypted, so this clone is the encrypted backup. The timer
# pulls the hub each hour. The pull is fast-forward only, so the timer never
# makes a merge commit and never changes local work.
#
# Make the clone once:
#
#   git clone coops@luna:/var/lib/luna/memory.git ~/org/luna
#
# Until the clone exists, the service does nothing.

let
  clone = "${config.home.homeDirectory}/org/luna";
in
{
  systemd.user.services.luna-memory-pull = {
    Unit.Description = "Pull the LUNA memory from the hub";
    Service = {
      Type = "oneshot";
      # A user service has a minimal PATH, and git needs ssh for the pull.
      Environment = [ "GIT_SSH_COMMAND=${pkgs.openssh}/bin/ssh -o BatchMode=yes" ];
      ExecStart = toString (pkgs.writeShellScript "luna-memory-pull" ''
        set -eu
        if [ ! -d "${clone}/.git" ]; then
          echo "No clone at ${clone}. Nothing to do."
          exit 0
        fi
        ${pkgs.git}/bin/git -C "${clone}" pull --ff-only --quiet
      '');
    };
  };

  systemd.user.timers.luna-memory-pull = {
    Unit.Description = "Pull the LUNA memory each hour";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;      # run after a suspend that missed the hour
      RandomizedDelaySec = "5m";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
