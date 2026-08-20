{ config, pkgs, lib, ... }:

# User-side language setup: where each toolchain writes, and how the shell
# finds it. The packages come from modules/languages.nix.

let
  goPath = "${config.home.homeDirectory}/.local/share/go";
in
{
  # -------------------------------------------------------------------
  # Go
  # -------------------------------------------------------------------
  programs.go = {
    enable = true;

    # go itself is a system package, so home-manager must not install a
    # second copy. Two go binaries on PATH is a version mismatch waiting
    # to happen.
    package = null;

    # home-manager writes these to ~/.config/go/env.
    #
    # CAUTION: that file becomes a read-only link into the Nix store.
    # `go env -w` fails against it. Set the variable here, then rebuild.
    env = {
      # The default GOPATH is ~/go. This keeps the home directory tidy.
      GOPATH = goPath;
      GOBIN = "${goPath}/bin";

      # Version management. `auto` makes the toolchain honour the `go` line
      # in go.mod. If a module asks for a version that is not installed, go
      # downloads that toolchain and runs it. The download goes to the
      # module cache under GOPATH, not to the Nix store.
      GOTOOLCHAIN = "auto";
    };

    # No usage reports to Google.
    telemetry.mode = "off";
  };

  # `go install` writes to GOBIN. Put GOBIN on PATH, or the tools that you
  # install are invisible.
  home.sessionPath = [ "${goPath}/bin" ];

  # -------------------------------------------------------------------
  # Node
  # -------------------------------------------------------------------
  # The fnm shell hook. It puts the selected Node version on PATH.
  #
  # --use-on-cd            change version when you enter a directory that
  #                        has a .nvmrc or a .node-version file
  # --version-file-strategy=recursive
  #                        also look in the parent directories, which is
  #                        what a monorepo needs
  # --corepack-enabled     let the selected Node supply yarn and pnpm
  #
  # Order 1400 puts this after home-manager's own PATH setup at order 1000.
  # fnm must go in front of that PATH, not behind it.
  programs.zsh.initContent = lib.mkOrder 1400 ''
    eval "$(${pkgs.fnm}/bin/fnm env --use-on-cd --version-file-strategy=recursive --corepack-enabled --shell zsh)"
  '';

  # fnm keeps the installed versions in $XDG_DATA_HOME/fnm. Nothing to
  # declare: fnm makes that directory on the first install.
  #
  # The versions are NOT reproducible. fnm downloads them at runtime, and a
  # new machine starts with none. That is the trade for a version manager.
  # If a project must pin its Node version reproducibly, give the project a
  # flake and a .envrc, and let direnv do it.
}
