{ config, pkgs, lib, ... }:

# The Liber8 floor: a live view of the vault at ~/Projects/liber8.
# Phoenix LiveView, no database, and it writes nothing into the record.
#
#   liber8-floor        start the server and open it in the browser
#   liber8-floor stop   stop the server
#
# WHY THIS FILE EXISTS. A process started inside the Hermes docker sandbox
# dies with the sandbox, and its ports are unreachable from this machine.
# Everything that has to outlive one agent session therefore belongs here,
# in a module, rather than in a terminal the agent opened. Until this file
# existed the floor could only be reached through a quick tunnel whose URL
# changed on every restart.
#
# LIKE GOD'S EYE VIEW, THE APP IS NOT A DERIVATION. Mix compiles into the
# checkout (_build, deps), and the app reads the vault and writes run state
# beside it. A read-only store path cannot hold that state, so a user
# service runs the git checkout in ~/Projects and Nix supplies only the
# runtime — Elixir and Erlang. See home/gods-eye-view.nix for the same
# shape applied to a Node application.
#
# THE SERVICE DOES NOT START AT LOGIN. The floor is a screen the Director
# looks at when he wants it; a BEAM VM holding memory for a screen nobody
# is reading is a cost with no benefit. The launcher starts it on demand.
#
# Update the app with `git pull` in the checkout. The next start refetches
# dependencies and recompiles when the sources or mix.lock changed.

let
  vault = "${config.home.homeDirectory}/Projects/liber8";
  checkout = "${config.home.homeDirectory}/Projects/liber8-floor";
  port = 4400;
  url = "http://localhost:${toString port}";

  elixir = pkgs.elixir;

  # Every binary the unit may run, because a systemd unit's PATH is exactly
  # this list and nothing else. The first version of this file supplied
  # elixir, git, coreutils and curl — and the service failed with
  # status=127 the moment the build script reached `make assets`, because
  # `make` lives in gnumake and not in coreutils. The journal is what showed
  # it: mix deps.get succeeded, and the very next command did not exist.
  #
  # bash is here because mix shells out for some tasks; findutils because
  # mix and git plumbing use find/xargs. Anything else that goes missing is
  # named by the preflight check at the top of the build script, rather than
  # surfacing as a bare 127.
  runtime = [
    elixir
    pkgs.bash
    pkgs.gnumake
    pkgs.findutils
    pkgs.git
    pkgs.coreutils
    pkgs.curl
  ];

  # Compile only when something moved — the same idea as the npm ci stamp
  # in gods-eye-view.nix. `mix deps.get` reaches the network, so it must
  # not run on every start.
  #
  # `mix local.hex` is idempotent, and required on a fresh machine: without
  # Hex, `mix deps.get` fails with "Could not find Hex, which is needed to
  # build and fetch dependencies".
  #
  # If the build fails, `liber8-floor` says so and points at the journal.
  # The failure is real information — this script never pretends to have
  # compiled something it did not.
  build = pkgs.writeShellScript "liber8-floor-build" ''
    set -eu

    # THE UNIT'S PATH IS EXACTLY WHAT THE MODULE SETS, so every command used
    # below must be named in `runtime` above. Check that first and fail with
    # the name of whatever is missing: without this the service died on
    # status=127 several seconds in, which says only that *something* was not
    # found — and one of the missing commands failed silently instead, which
    # is worse.
    for c in mix make git cat sha256sum cut sort; do
      command -v "$c" >/dev/null 2>&1 || {
        echo "liber8-floor: required command not on the unit PATH: $c" >&2
        exit 1
      }
    done

    mkdir -p _build
    stamp=_build/.nyx-src-sha256
    # No xargs here, deliberately. The first version piped `git ls-files`
    # through `xargs -r cat` with stderr sent to /dev/null: xargs is in
    # findutils, which was not on the PATH, so the hash was computed from
    # partial input, the stamp never matched, and the build re-ran on every
    # start with nothing in the journal to say why. A silent wrong answer is
    # worse than a loud failure.
    want=$({ cat mix.lock mix.exs
             git ls-files 'lib/*' 'config/*' 'priv/*' 'test/*' 'Makefile' \
               | LC_ALL=C sort | while read -r f; do cat "$f"; done
           } | sha256sum | cut -d' ' -f1)
    if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$want" ]; then
      exit 0
    fi
    echo "liber8-floor: sources or dependencies changed — fetching and compiling" >&2
    mix local.hex --force
    mix local.rebar --force
    mix deps.get
    # The LiveView JavaScript is COPIED out of deps/, never built: there is
    # no node, no npm and no asset pipeline in this project. One less thing
    # to break, and it keeps the build offline-capable.
    make assets
    mix compile
    echo "$want" > "$stamp"
  '';

  liber8-floor = pkgs.writeShellScriptBin "liber8-floor" ''
    set -eu
    notify() { ${pkgs.libnotify}/bin/notify-send -a "Liber8 floor" "$@"; }

    if [ "''${1:-}" = stop ]; then
      systemctl --user stop liber8-floor.service
      exit 0
    fi

    if [ ! -f "${checkout}/mix.exs" ]; then
      notify -u critical "No checkout" "Clone the repository into ${checkout}"
      exit 1
    fi

    # The first start fetches dependencies and compiles. That can take a
    # minute or two on a cold _build.
    if ! systemctl --user is-active --quiet liber8-floor.service; then
      notify "Starting" "The first start fetches and compiles. Wait."
    fi
    if ! systemctl --user start liber8-floor.service; then
      notify -u critical "Start failed" "Run: journalctl --user -u liber8-floor"
      exit 1
    fi

    # The unit is active before the endpoint listens. Wait for the port.
    i=0
    until ${pkgs.curl}/bin/curl -fs -o /dev/null "${url}/"; do
      i=$((i + 1))
      if [ "$i" -ge 120 ]; then
        notify -u critical "No answer" "Run: journalctl --user -u liber8-floor"
        exit 1
      fi
      sleep 1
    done

    exec brave "--app=${url}" "--class=localhost__"
  '';
in
{
  home.packages = [ liber8-floor ];

  systemd.user.services.liber8-floor = {
    Unit = {
      Description = "Liber8 floor on ${url} — a live view of the vault";
      # The checkout must exist. Without this the unit fails on every start
      # and, with Restart, would spin; the launcher's own check is the
      # friendly version of the same guard.
      ConditionPathExists = "${checkout}/mix.exs";
      # Stop the restarts after 3 failures in 2 minutes. Without a limit, a
      # start that always fails restarts every 5 seconds without end.
      StartLimitIntervalSec = 120;
      StartLimitBurst = 3;
    };
    Service = {
      WorkingDirectory = checkout;
      Environment = [
        "PATH=${lib.makeBinPath runtime}"
        "MIX_ENV=dev"
        # The vault the floor reads. It is never written to.
        "LIBER8=${vault}"
        "FLOOR_PORT=${toString port}"
        # LOOPBACK ONLY, and the app honours this variable — before it
        # existed, a module set BIND and the app ignored it, which is a
        # setting that looks like a control and is not one.
        #
        # The screen has NO authentication and shows company state: who is
        # blocked on what, what is unpriced, what is being decided. Bound to
        # every interface on a laptop that joins cafe networks, that is an
        # open door. Opening the floor to the internet does not require
        # opening this — a tunnel or a reverse proxy connects over loopback.
        "FLOOR_BIND=127.0.0.1"
      ];
      ExecStartPre = toString build;
      ExecStart = "${elixir}/bin/mix phx.server";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
