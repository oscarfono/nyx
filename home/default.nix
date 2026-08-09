{ config, pkgs, lib, username, fullName, email, hostName, ... }:

# User layer. Everything here is Nyx's own.

{
  imports = [ ./emacs.nix ./desktop.nix ./menu.nix ./wallpaper.nix ./tools.nix ];

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

    # home-manager moved git config under `settings` upstream. userName,
    # userEmail and extraConfig are all folded in here now.
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
