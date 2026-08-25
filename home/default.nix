{ config, pkgs, lib, username, fullName, email, hostName, ... }:

# User layer. Everything here is Nyx's own.

{
  imports = [
    ./emacs.nix
    ./desktop.nix
    ./menu.nix
    ./wallpaper.nix
    ./tools.nix
    ./theme.nix
    ./agents.nix
    ./treesitter.nix
    ./languages.nix
    ./dictation.nix
    ./xdg.nix
    ./bat.nix
    ./webapps.nix
    ./colours.nix
    ./msf.nix
    ./proton.nix
    ./secops.nix
    ./report.nix
    ./local.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  # -------------------------------------------------------------------
  # Directories
  # -------------------------------------------------------------------
  # systemd-tmpfiles, not an activation script. Declarative, runs on a
  # timer as well as at boot, and cannot take the rest of activation down
  # with it if it fails.
  #   ~/.shh    secrets, referenced by early-init.el. Owner-only.
  #   ~/Videos  target for the screen-recording bind.
  systemd.user.tmpfiles.rules = [
    "d %h/.shh 0700 - - -"
    "d %h/Videos 0755 - - -"
  ];

  # -------------------------------------------------------------------
  # Shell
  # -------------------------------------------------------------------
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # Runs before home-manager's own blocks, which is what matters here:
    # the Ghostty integration must not have loaded yet.
    #
    # Ghostty exports GHOSTTY_RESOURCES_DIR into the session, so Emacs and
    # everything it spawns inherits it. home-manager's generated .zshrc
    # sources Ghostty's shell integration whenever that path is readable —
    # it checks for the file, not for the terminal. Inside Emacs `eat` that
    # integration emits Ghostty-specific escape sequences for cursor
    # position and bracketed paste, which eat does not implement: keystrokes
    # duplicate on redraw and paste corrupts.
    #
    # Unsetting it outside Ghostty makes the existing guard do what it looks
    # like it already does.
    initContent = lib.mkOrder 550 ''
      if [[ "$TERM" != xterm-ghostty ]]; then
        unset GHOSTTY_RESOURCES_DIR
      fi
    '';

    shellAliases = {
      e = "emacsclient -c -a ''";
      ls = "eza --icons --group-directories-first";
      ll = "eza -l --icons --group-directories-first --git";
      cat = "bat";
      terraform = "tofu";   # muscle memory, minus the licence
      rebuild = "sudo nixos-rebuild switch --flake ~/Projects/nyx#${hostName}";
      update = "nix flake update --flake ~/Projects/nyx";
    };
  };

  programs.starship.enable = true;
  programs.fzf.enable = true;
  programs.direnv = { enable = true; nix-direnv.enable = true; };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = false;   # Emacs holds that title
    extraPackages = with pkgs; [ nil lua-language-server ripgrep fd ];
  };

  # -------------------------------------------------------------------
  # Git
  # -------------------------------------------------------------------
  programs.git = {
    enable = true;
    signing.signByDefault = true;
    # signing.key = "YOUR-GPG-KEY-ID";

    # A GLOBAL ignore file, not a per-repo .gitignore. Claude Code writes
    # .claude/ and CLAUDE.local.md into whatever project it runs in; those
    # are local config and session state, and must never reach a remote.
    # Doing it globally means it holds for every repo, including ones cloned
    # in future and ones belonging to other people.
    #
    # These files are still backed up: restic takes ~/Projects and only
    # excludes .git, node_modules and build output.
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
      commit.gpgsign = true;
    };
  };

  # -------------------------------------------------------------------
  # KeePassXC
  # -------------------------------------------------------------------
  # The database itself is not managed by Nix, only the client config.
  # Put the .kdbx on the encrypted root, back it up to your own storage.
  xdg.configFile."keepassxc/keepassxc.ini".text = ''
    [General]
    ConfigVersion=2
    MinimizeAfterUnlock=true

    [Browser]
    Enabled=true
    AllowExpiredCredentials=false

    [Security]
    ClearClipboardTimeout=15
    LockDatabaseIdle=true
    LockDatabaseIdleSeconds=300
    LockDatabaseScreenLock=true
  '';
}
