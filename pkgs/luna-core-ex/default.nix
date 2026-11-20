{ lib, beamPackages, git }:

let
  pname = "luna-core-ex";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./mix.exs ./mix.lock ./config ./lib ./test ];
  };
in
beamPackages.mixRelease {
  inherit pname version src;

  # Change the hash after each change to mix.lock. Refer to "Dependencies"
  # in luna/LUNA.org.
  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "${pname}-deps";
    inherit version src;
    hash = "sha256-BuFdPg5s/GWG8/S37rJLd/f1a+AGTB9lSwWDy2WHyFQ=";
  };

  doCheck = true;
  nativeCheckInputs = [ git ];
  checkPhase = ''
    runHook preCheck
    # The deps are compiled for prod only. Compile them for test from the
    # sources in deps/. This step needs no network.
    MIX_ENV=test mix deps.compile
    MIX_ENV=test mix test --no-deps-check
    runHook postCheck
  '';

  meta = {
    description = "The LUNA core, in Elixir. It replaces pkgs/luna-core at the cutover.";
    mainProgram = "luna_core";
  };
}
