{ config, pkgs, lib, ... }:

# God's Eye View: a 3D globe in the browser. It shows live aircraft, ships,
# satellites, earthquakes and public cameras.
#
#   gods-eye-view        start the server and open the app window
#   gods-eye-view stop   stop the server
#
# The app is NOT a derivation. The Vite dev server IS the app: it serves the
# client and runs the API proxies as middleware. The app also writes its
# settings and API keys into the checkout. A read-only store path cannot
# hold that state. Thus a user service runs the git checkout in ~/Projects,
# and Nix supplies only the Node runtime.
#
# Update the app with `git pull` in the checkout. The service runs `npm ci`
# at the next start when package-lock.json changed.
#
# Set the API keys in the app (Provider Settings), or in .env in the
# checkout. git ignores .env. The keys never go into this repo.
#
# The service does not start at login. Vite and Cesium use a lot of memory
# on a 16GB machine, so the launcher starts the service on demand.

let
  checkout = "${config.home.homeDirectory}/Projects/gods-eye-view";
  url = "http://localhost:4173";

  # package.json permits Node ">=24.14.0 <25 || >=26 <27". The nixpkgs
  # default `nodejs` can move outside that range at a flake update, so pin
  # the major version here.
  node = pkgs.nodejs_24;

  # npm ci deletes node_modules and installs exactly the lockfile. Unlike
  # npm install, it never writes package-lock.json, so `git pull` stays a
  # fast-forward. The stamp records the lockfile hash of the last install.
  install = pkgs.writeShellScript "gods-eye-view-install" ''
    set -eu
    stamp=node_modules/.nyx-lock-sha256
    want=$(sha256sum package-lock.json | cut -d' ' -f1)
    if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$want" ]; then
      exit 0
    fi
    echo "gods-eye-view: package-lock.json changed, running npm ci" >&2
    npm ci --no-audit --no-fund
    echo "$want" > "$stamp"
  '';

  gods-eye-view = pkgs.writeShellScriptBin "gods-eye-view" ''
    set -eu
    notify() { ${pkgs.libnotify}/bin/notify-send -a "God's Eye View" "$@"; }

    if [ "''${1:-}" = stop ]; then
      systemctl --user stop gods-eye-view.service
      exit 0
    fi

    if [ ! -f "${checkout}/package.json" ]; then
      notify -u critical "No checkout" "Clone the repo into ${checkout}"
      exit 1
    fi

    # The first start runs npm ci. That step can take some minutes.
    if ! systemctl --user is-active --quiet gods-eye-view.service; then
      notify "Starting" "The first start installs packages. Wait."
    fi
    if ! systemctl --user start gods-eye-view.service; then
      notify -u critical "Start failed" "Run: journalctl --user -u gods-eye-view"
      exit 1
    fi

    # The unit is active before Vite listens. Wait for the port.
    i=0
    until ${pkgs.curl}/bin/curl -fs -o /dev/null "${url}/"; do
      i=$((i + 1))
      if [ "$i" -ge 120 ]; then
        notify -u critical "No answer" "Run: journalctl --user -u gods-eye-view"
        exit 1
      fi
      sleep 1
    done

    exec brave "--app=${url}" "--class=localhost__"
  '';
in
{
  home.packages = [ gods-eye-view ];

  systemd.user.services.gods-eye-view = {
    Unit = {
      Description = "God's Eye View dev server on ${url}";
      ConditionPathExists = "${checkout}/package.json";
    };
    Service = {
      WorkingDirectory = checkout;
      Environment = [
        # npm finds the node binary on PATH. Vite runs git for some build
        # metadata.
        "PATH=${lib.makeBinPath [ node pkgs.git pkgs.coreutils ]}"
        # Only the QA scripts use puppeteer. Its Chromium download is
        # 150MB, and that binary does not start on NixOS.
        "PUPPETEER_SKIP_DOWNLOAD=1"
      ];
      ExecStartPre = toString install;
      # --strictPort stops Vite when 4173 is in use. Without it, Vite moves
      # to another port, and the launcher waits on the wrong port.
      ExecStart = "${node}/bin/npm run dev -- --strictPort";
      # npm ci downloads some hundred MB at the first start.
      TimeoutStartSec = "15min";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  xdg.desktopEntries.gods-eye-view = {
    name = "God's Eye View";
    exec = "gods-eye-view";
    icon = "brave-browser";
    categories = [ "Network" "Education" ];
    terminal = false;
    settings.StartupWMClass = "brave-localhost__-Default";
  };
}
