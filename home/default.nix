{ config, pkgs, lib, ... }:

{
  imports = [ ./emacs.nix ];

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
  programs.fish = {
    enable = true;
    shellAliases = {
      v = "nvim";
      e = "emacsclient -c -a ''";
      ls = "eza --icons --group-directories-first";
      ll = "eza -l --icons --group-directories-first --git";
      cat = "bat";
      grep = "rg";
      rebuild = "sudo nixos-rebuild switch --flake ~/nyx#beta";
      update = "nix flake update --flake ~/nyx";
    };
  };

  programs.starship = {
    enable = true;
    settings.add_newline = false;
  };

  programs.fzf.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # -------------------------------------------------------------------
  # Git
  # -------------------------------------------------------------------
  programs.git = {
    enable = true;
    userName = "Coops";
    userEmail = "CHANGE-ME@example.com";
    signing.signByDefault = true;
    # signing.key = "YOUR-GPG-KEY-ID";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      commit.gpgsign = true;
    };
  };

  # -------------------------------------------------------------------
  # Terminal
  # -------------------------------------------------------------------
  programs.alacritty = {
    enable = true;
    settings = {
      window.padding = { x = 12; y = 12; };
      window.opacity = 0.95;
      font.normal.family = "JetBrainsMono Nerd Font";
      font.size = 11;
    };
  };

  # -------------------------------------------------------------------
  # Neovim
  # -------------------------------------------------------------------
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = false;   # Emacs holds that title
    extraPackages = with pkgs; [ nil lua-language-server ripgrep fd ];
  };

  # -------------------------------------------------------------------
  # Hyprland
  # -------------------------------------------------------------------
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      "$mod" = "SUPER";
      "$terminal" = "alacritty";

      monitor = ",preferred,auto,1.25";   # T490s is 14in 1080p, 1.25 is comfortable

      general = {
        gaps_in = 4;
        gaps_out = 8;
        border_size = 2;
        "col.active_border" = "rgba(3a3a3aee)";
        "col.inactive_border" = "rgba(1a1a1aaa)";
        layout = "dwindle";
      };

      decoration = {
        rounding = 6;
        blur.enabled = false;   # saves battery, and this is not a demo machine
      };

      animations.enabled = true;

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        touchpad.natural_scroll = true;
      };

      exec-once = [
        "waybar"
        "mako"
        "hypridle"
        "hyprpaper"
        "wl-paste --watch cliphist store"
      ];

      bind = [
        "$mod, Return, exec, $terminal"
        "$mod, E, exec, emacsclient -c -a ''"
        "$mod, B, exec, brave"
        "$mod SHIFT, B, exec, firefox"
        "$mod, P, exec, keepassxc"
        "$mod, Space, exec, wofi --show drun"
        "$mod, Q, killactive,"
        "$mod, F, fullscreen,"
        "$mod, V, togglefloating,"
        "$mod SHIFT, L, exec, hyprlock"
        ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
      ]
      ++ builtins.concatLists (builtins.genList
        (i: let ws = toString (i + 1); in [
          "$mod, ${ws}, workspace, ${ws}"
          "$mod SHIFT, ${ws}, movetoworkspace, ${ws}"
        ]) 9);

      bindel = [
        ",XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ",XF86MonBrightnessUp, exec, brightnessctl s 5%+"
        ",XF86MonBrightnessDown, exec, brightnessctl s 5%-"
      ];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
      };
      listener = [
        { timeout = 300; on-timeout = "loginctl lock-session"; }
        { timeout = 600; on-timeout = "systemctl suspend"; }
      ];
    };
  };

  programs.hyprlock = {
    enable = true;
    settings.background = [{ color = "rgba(10,10,10,1.0)"; }];
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
