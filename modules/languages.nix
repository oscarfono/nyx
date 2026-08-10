{ config, pkgs, lib, ... }:

# Per-language tooling: LSP servers, formatters, linters.
#
# Nix supplies the binaries; the editor discovers them on PATH. That keeps
# the split clean — Emacs (eglot) and Neovim both find the same servers, and
# neither downloads anything at runtime.
#
# Import from hosts/<host>/default.nix.

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
    basedpyright              # LSP, faster fork of pyright
    ruff                      # linter + formatter, replaces black/isort/flake8

    # Web / JSON / YAML
    typescript-language-server
    vscode-langservers-extracted   # html, css, json, eslint
    yaml-language-server
    nodePackages.prettier

    # Go
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
    dockerfile-language-server-nodejs

    # Markdown / prose
    marksman
    vale                      # prose linter

    # C/C++ (also what native-comp and vterm need)
    clang-tools               # clangd + clang-format
  ];

  # Emacs 30 uses eglot, which finds these on PATH with no configuration for
  # most languages. The mode hooks belong in .emacs.d, not here:
  #
  #   (add-hook 'python-ts-mode-hook #'eglot-ensure)
  #   (add-hook 'nix-mode-hook #'eglot-ensure)
  #
  # Tree-sitter grammars come from home/treesitter.nix.
}
