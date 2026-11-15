{ pkgs, lib, ... }:

# ant: the official CLI for the Claude API. https://github.com/anthropics/anthropic-cli
#
#   ant auth login       log in with the Claude Console account
#   ant models list      make sure that the login works
#   ant --help           the CLI
#
# CAUTION: `ant` in nixpkgs is Apache Ant, the Java build tool. This file
# builds the Anthropic CLI from source with the same name. Do not also add
# pkgs.ant to the packages, because the two binaries collide.
#
# To update ant, change `version`. Then set both hashes to lib.fakeHash and
# rebuild. Each failure prints the correct hash.

let
  version = "2.9.0";

  # go.mod at v2.9.0 asks for Go 1.26.10. On 2026-11-15, nixpkgs has
  # 1.26.9 in the 1.26 line, so this uses the 1.27 line.
  ant = pkgs.buildGo127Module {
    pname = "ant";
    inherit version;

    src = pkgs.fetchFromGitHub {
      owner = "anthropics";
      repo = "anthropic-cli";
      rev = "v${version}";
      hash = "sha256-bjc2xaiyV5Lj+c8Oksmu3/Ij3J5+qj5Qak+yRlF4lJA=";
    };

    vendorHash = "sha256-j5JWaXTl6eDWVfcyyctZsFOWMdawmnqOAsCBSqig/jI=";

    subPackages = [ "cmd/ant" ];

    # The same flags as the upstream .goreleaser.yml.
    env.CGO_ENABLED = 0;
    ldflags = [ "-s" "-w" "-X main.version=${version}" ];

    nativeBuildInputs = [ pkgs.installShellFiles ];

    # The upstream release makes the completions and the man pages with the
    # binary itself. This does the same.
    postInstall = ''
      installShellCompletion --cmd ant \
        --bash <($out/bin/ant @completion bash) \
        --zsh <($out/bin/ant @completion zsh) \
        --fish <($out/bin/ant @completion fish)
      $out/bin/ant @manpages -o man
      installManPage man/man1/*
    '';

    meta = {
      description = "The CLI for the Claude API";
      homepage = "https://github.com/anthropics/anthropic-cli";
      license = lib.licenses.asl20;
      mainProgram = "ant";
    };
  };
in
{
  home.packages = [ ant ];
}
