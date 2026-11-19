# UNBUILT — 19 November 2026. Written in the agent's sandbox, which has no Nix,
# so this file has NEVER BEEN EVALUATED. Everything in it is either read from
# nixpkgs source or from disko's own examples on the day it was written; the
# list of what was verified and what was assumed is in hosts/vps/README.md.
#
# The command that settles it, from the machine with the flake on it:
#
#     nixos-rebuild build --flake ~/Projects/nyx#vps
#
# It evaluates and builds and does not switch, and it names any option it does
# not recognise. Run it before the box is worth anything.

{ config, pkgs, lib, inputs, username, fullName, email, hostName, ... }:

# The user layer for a machine nobody sits in front of.
#
# home/default.nix is the desktop: 25 files of shell, editor, theme, terminal
# and wallpaper. None of it belongs on a server, and all of it costs store
# space and an evaluation. This is the trimmed set — the agent, the floor, and
# the handful of things the agent's own tooling assumes.
{
  imports = [
    ./hermes.nix          # the gateway, the sandbox mounts, the commit identity
    ./liber8-floor.nix    # the company's own screen
    ./xdg.nix             # something will always ask for XDG dirs
    ./local.nix           # his own file, not in the repo
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;

  systemd.user.tmpfiles.rules = [
    "d %h/.shh 0700 - - -"
  ];

  # Git, with NO signing key and NO signature — the same rule the sandbox
  # already follows: a machine that holds no private key cannot sign, and an
  # unsigned commit is honest about that. The Director signs on the T490.
  programs.git = {
    enable = true;
    signing.signByDefault = false;
    ignores = [
      ".claude/"
      "CLAUDE.local.md"
      ".claude.json"
      ".mcp.json"
      ".direnv/"
      "result"
      "result-*"
      ".DS_Store"
    ];
    settings = {
      user = {
        name = fullName;
        email = email;
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      commit.gpgsign = false;
    };
  };

  # A short shell. The desktop's zsh carries emacs and terminal integrations
  # that have no meaning here.
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      rebuild = "sudo nixos-rebuild switch --flake ~/Projects/nyx#${hostName}";
      update = "nix flake update --flake ~/Projects/nyx";
    };
  };
  programs.starship.enable = true;
}
