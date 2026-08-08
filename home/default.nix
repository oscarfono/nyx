{ config, pkgs, lib, ... }:

# User layer. Everything here is Nyx's own.

{
  imports = [ ./emacs.nix ./desktop.nix ./menu.nix ./wallpaper.nix ];

  home.username = "coops";
  home.homeDirectory = "/home/coops";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  # -------------------------------------------------------------------
  # Secrets directory
  # -------------------------------------------------------------------
  # ~/.shh holds .authinfo.gpg, referenced by early-init.el. Created at
  # activation with 0700 so only the owner can read, write or traverse it.
  # home.file cannot express an empty directory with a mode, so this is one
  # of the few places an activation script is the right tool.
  home.activation.createShhDir =
    config.lib.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p "$HOME/.shh"
      $DRY_RUN_CMD chmod 0700 "$HOME/.shh"
    '';

  # -------------------------------------------------------------------
  # Shell
  # -------------------------------------------------------------------
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      e = "emacsclient -c -a ''";
      ls = "eza --icons --group-directories-first";
      ll = "eza -l --icons --group-directories-first --git";
      cat = "bat";
      terraform = "tofu";   # muscle memory, minus the licence
      rebuild = "sudo nixos-rebuild switch --flake ~/nyx#beta";
      update = "nix flake update --flake ~/nyx";
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

    # home-manager moved git config under `settings` upstream. userName,
    # userEmail and extraConfig are all folded in here now.
    settings = {
      user = {
        name = "Cooper Oscarfono";
        email = "cooper@oscarfono.com";
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
