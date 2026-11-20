{ lib, beamPackages, postgresql_18, fetchurl, jetbrains-mono }:

let
  pname = "luna-web";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./mix.exs ./mix.lock ./config ./lib ./priv ./test ];
  };
  # The fonts of the page. The page loads nothing from the internet, so luna
  # serves them. Space Grotesk is not in nixpkgs: the build fetches it once
  # from the Google Fonts repository (OFL), pinned to a commit and a hash.
  spaceGrotesk = fetchurl {
    name = "SpaceGrotesk.ttf";
    url = "https://raw.githubusercontent.com/google/fonts/00a38a53f92aef923b9353f40128e8f4552ddae4/ofl/spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf";
    hash = "sha256-rK1t4fyTQ29cDx9BN3Ue8E8a6jBj5wNlNZcP/PvXn3I=";
  };
in
beamPackages.mixRelease {
  inherit pname version src;

  # Change the hash after each change to mix.lock. Refer to "Dependencies"
  # in luna/LUNA.org.
  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "${pname}-deps";
    inherit version src;
    hash = "sha256-4/l12IHvIY9mUvgHOPBlrBy49wSfFYeWneE/KYeOg+Y=";
  };

  preBuild = ''
    mkdir -p priv/static/fonts
    cp ${spaceGrotesk} priv/static/fonts/SpaceGrotesk.ttf
    cp ${jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Regular.ttf priv/static/fonts/
  '';

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
