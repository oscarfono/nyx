{ lib, beamPackages, postgresql_18 }:

let
  pname = "luna-web";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./mix.exs ./mix.lock ./config ./lib ./priv ./test ];
  };
in
beamPackages.mixRelease {
  inherit pname version src;

  # Change the hash after each change to mix.lock. Refer to "Dependencies"
  # in luna/LUNA.org.
  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "${pname}-deps";
    inherit version src;
    hash = "sha256-grka9MK6rgUdz6ma5LtsY/ZHipdqMdM1vaBuEHUedxk=";
  };

  # The tests need a PostgreSQL server. The check starts one in the build
  # directory, with a unix socket only.
  doCheck = true;
  nativeCheckInputs = [ postgresql_18 ];
  checkPhase = ''
    runHook preCheck
    export PGDATA=$TMPDIR/pg PGHOST=$TMPDIR/pgsock PGUSER=luna_test
    mkdir -p $PGHOST
    initdb -A trust -U $PGUSER >/dev/null
    pg_ctl -w -o "-k $PGHOST -c listen_addresses=" -l $TMPDIR/pg.log start
    MIX_ENV=test mix test --no-deps-check || { pg_ctl -m fast stop; exit 1; }
    pg_ctl -m fast stop
    runHook postCheck
  '';

  meta = {
    description = "The LUNA web app, in Phoenix LiveView";
    mainProgram = "luna_web";
  };
}
