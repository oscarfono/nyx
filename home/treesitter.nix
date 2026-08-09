{ config, pkgs, lib, ... }:

# Tree-sitter grammars for Emacs. Home-manager module.
#
# Emacs 30 has tree-sitter built in but ships NO grammars: it expects to
# download and compile them at runtime, which needs a toolchain and network
# and produces untracked binaries in your home directory.
#
# Nix has them prebuilt. This symlinks the whole set where Emacs looks, so
# treesit-language-available-p is true for everything from first launch and
# M-x treesit-install-language-grammar is never needed.

{
  home.file.".emacs.d/tree-sitter".source =
    "${pkgs.emacsPackages.treesit-grammars.with-all-grammars}/lib";
}
