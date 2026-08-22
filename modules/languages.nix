{ config, pkgs, lib, ... }:

# Per-language tooling: runtimes, LSP servers, formatters, linters.
#
# Nix supplies the binaries; the editor discovers them on PATH. That keeps
# the split clean — Emacs (eglot) and Neovim both find the same servers, and
# neither downloads anything at runtime.
#
# The user-side half of this module is home/languages.nix. That module sets
# GOPATH, GOTOOLCHAIN and the fnm shell hook.
#
# Import from flake.nix, in desktopModules.

{
  environment.systemPackages = with pkgs; [


    # Nix
    nil                       # LSP
    nixfmt-rfc-style          # formatter
    statix                    # linter
    deadnix                   # dead code

    # Shell
    bash-language-server
    shellcheck
    shfmt

    # Python
    #
    # python3 is the interpreter. basedpyright and ruff analyse code, but
    # neither one runs code. Without python3 there is no interpreter at all.
    python3
    basedpyright              # LSP, faster fork of pyright
    ruff                      # linter + formatter, replaces black/isort/flake8

    # Node
    #
    # nodejs is the baseline, the same pattern as go above: the system
    # supplies one version, and a per-project version manager replaces that
    # version when a project asks for a different one. fnm shows the
    # baseline as the `system` version.
    #
    # Without a baseline, a directory that has no .node-version file gives
    # no node at all.
    #
    # CAUTION: `npm install -g` fails against the baseline, because the
    # baseline lives in the read-only store. Select an fnm version first,
    # then install the global package.
    nodejs

    # fnm must be on PATH, not only in the eval in home/languages.nix.
    # `fnm env --use-on-cd` writes a zsh hook that calls `fnm` by name:
    #
    #   _fnm_autoload_hook () { fnm use --silent-if-unchanged }
    #
    # The hook runs on every cd. If fnm is not on PATH, each cd fails with
    # "fnm: command not found".
    fnm

    # Web / JSON / YAML
    typescript-language-server
    vscode-langservers-extracted   # html, css, json, eslint
    yaml-language-server
    prettier

    # Go
    go
    gopls
    gotools

    # Rust
    rust-analyzer
    rustfmt

    # Lua
    lua-language-server
    stylua

    # Infra
    terraform-ls
    ansible-language-server
    dockerfile-language-server

    # Markdown / prose
    marksman
    vale                      # prose linter

    # C/C++ (also what native-comp and vterm need)
    clang-tools               # clangd + clang-format
  ];

  # fnm downloads the official Node builds from nodejs.org. Those builds are
  # dynamically linked, and they ask for a loader at
  # /lib64/ld-linux-x86-64.so.2. That path does not exist on NixOS, so the
  # downloaded node exits with "No such file or directory" even though the
  # file is there. nix-ld supplies the loader and a base set of libraries.
  # Without nix-ld, fnm installs a Node that cannot start.
  #
  # This also fixes the same class of failure for other downloaded binaries:
  # language server installers, prebuilt npm native modules, and the VS Code
  # server that a remote IDE drops in ~/.vscode-server.
  programs.nix-ld.enable = true;

  # Emacs 30 uses eglot, which finds these on PATH with no configuration for
  # most languages. The mode hooks belong in .emacs.d, not here:
  #
  #   (add-hook 'python-ts-mode-hook #'eglot-ensure)
  #   (add-hook 'nix-mode-hook #'eglot-ensure)
  #
  # Tree-sitter grammars come from home/treesitter.nix.
}
