{ config, pkgs, lib, ... }:

# REA (Reverse Engineer Anything): one MCP server that lets an agent inspect
# native binaries, Android APKs, Electron apps, .NET assemblies, firmware,
# packet captures and websites. https://github.com/morluto/rea
#
#   rea --help           the CLI
#   rea doctor           show which engines REA finds
#   claude               the MCP server and the skill are already registered
#
# modules/secops.nix supplies the engines: Ghidra, JADX, Rizin and more.
# This file supplies the `rea` wrapper and registers REA with Claude Code.
#
# The REA package is NOT a derivation. The npm package has no lockfile, and
# the package has native parts: node-pty prebuilds, and frida, which
# downloads a binary at install. REA's own docs give the persistent
# registration as `npx -y rea-agents@<exact version> mcp`, so this file
# uses that form. npx caches the package in ~/.npm.
#
# To update REA, change `version`, then change the hash of `skillSrc`. The
# version of the skill and the version of the server must agree. `rea update`
# and `rea setup` do not work here, because Nix owns the registration.

let
  version = "6.8.0";

  # REA asks for Node ">=24.22.1" in the 24 line. On 2026-10-26, nixpkgs
  # has 24.21.0, and no other Node line meets the range either. npm only
  # warns about the engines field, and REA uses the range only in `rea
  # doctor` and `rea setup`. Change to the newer Node when nixpkgs has it.
  node = pkgs.nodejs_24;

  # The skill from the same release as the server, with a pinned hash.
  skillSrc = pkgs.fetchzip {
    url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${version}.tgz";
    hash = "sha256-Zbi8ttwO9SjVAB0FXs4dFIe1ifQxNbmZ/Su9MJ7OBVE=";
  };

  # The headless JADX bridge for APK analysis. The hash is the digest that
  # REA pins in src/android/JadxRelease.ts.
  jadxBridge = pkgs.fetchurl {
    url = "https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar";
    hash = "sha256-bl6s9QC2QpK/tzxJeXwZWPbuRGRuQ+hoA5rn/rVz/3U=";
  };

  # Ghidra and the JADX bridge both need a full JDK with javac. The nixpkgs
  # Ghidra uses JDK 21.
  jdk = pkgs.jdk21;

  pwntools = pkgs.python3.withPackages (ps: [ ps.pwntools ]);

  rea = pkgs.writeShellScriptBin "rea" ''
    set -eu

    case "''${1:-}" in
      update|--update|setup)
        echo "rea: Nix manages REA. Change the version in home/rea.nix, then rebuild." >&2
        exit 1
        ;;
    esac

    # PREPEND to PATH, and do not replace it. npx starts the package with
    # sh, and REA needs a procps ps for its process ownership checks.
    export PATH="${lib.makeBinPath [ node pkgs.procps jdk ]}:$PATH"

    # GHIDRA_INSTALL_DIR always wins over a search of PATH.
    export GHIDRA_INSTALL_DIR="${pkgs.ghidra}/lib/ghidra"
    export JAVA_HOME="${jdk}"
    export REA_JADX_MCP_JAR="${jadxBridge}"
    export REA_PWNTOOLS_PYTHON="${pwntools}/bin/python3"
    export REA_APKTOOL_COMMAND="${pkgs.apktool}/bin/apktool"
    export REA_ADB_PATH="${pkgs.android-tools}/bin/adb"
    export REA_MITMDUMP_COMMAND="${pkgs.mitmproxy}/bin/mitmdump"
    export REA_SIGROK_COMMAND="${pkgs.sigrok-cli}/bin/sigrok-cli"
    export REA_TSHARK_COMMAND="${pkgs.tshark}/bin/tshark"
    export REA_OBJDUMP_COMMAND="${pkgs.binutils-unwrapped}/bin/objdump"

    # Chromium, and not Brave. The Brave policies in modules/apps.nix are
    # for browsing, and REA drives the browser through the DevTools
    # protocol.
    export REA_BROWSER_EXECUTABLE="${pkgs.chromium}/bin/chromium"

    # Hopper and IDA are commercial, and neither one is installed.
    export REA_ANALYSIS_PROVIDER="''${REA_ANALYSIS_PROVIDER:-ghidra}"

    exec npx --yes "rea-agents@${version}" "$@"
  '';
in
{
  home.packages = [ rea ];

  # home-manager writes the server and the skill into a personal plugin
  # under ~/.claude/skills. It does not write settings.json or
  # ~/.claude.json, so the settings that you edit stay yours.
  #
  # package = null, because modules/apps.nix installs Claude Code. With a
  # package, home-manager installs a second copy.
  #
  # The MCP tools appear as mcp__plugin_hm_rea__<tool>.
  programs.claude-code = {
    enable = true;
    package = null;

    mcpServers.rea = {
      command = "${rea}/bin/rea";
      args = [ "mcp" ];
    };

    skills.reverse-engineer-anything = "${skillSrc}/skills/reverse-engineer-anything";
  };
}
