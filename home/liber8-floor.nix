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

  # Elixir brings Erlang with it. git is needed to read provenance and to
  # list the sources for the stamp below; curl for the launcher's wait.
  runtime = [ elixir pkgs.git pkgs.coreutils pkgs.curl ];

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
    mkdir -p _build
    stamp=_build/.nyx-src-sha256
    want=$({ cat mix.lock mix.exs
             git ls-files 'lib/*' 'config/*' 'priv/*' 'test/*' 'Makefile' \
               | xargs -r cat 2>/dev/null
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
