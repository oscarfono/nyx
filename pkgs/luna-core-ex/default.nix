{ lib, beamPackages, git, hledger }:

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
    hash = "sha256-TvDqfzeeC55gKZO2R2o4juDH99tV9pl7gdQ7+lwnp1E=";
  };

  doCheck = true;
  # The money tests run hledger. The memory tests run git.
  nativeCheckInputs = [ git hledger ];
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
