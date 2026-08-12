{ config, pkgs, lib, ... }:

# Everything a user actually launches. Opinionated by design.
# Emacs lives in modules/emacs.nix, not here.

{
  # Unfree is opt-in per package. This list is the complete inventory of
  # non-free software on the machine.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "brave"
      "claude-code"
      # Steam and friends, enabled by modules/gaming.nix.
      "steam"
      "steam-unwrapped"
      "steam-original"
      "steam-run"

      # Security tooling. Both are commercial products with free tiers;
      # nixpkgs ships the community/free editions but they are still
      # non-free licences.
      "burpsuite"
    ];

  environment.systemPackages = with pkgs; [
    # Browsers. Brave is the default, Firefox is the escape hatch.
    brave
    firefox

    # Credentials. KeePassXC with a local kdbx, no cloud vendor in the loop.
    keepassxc

    # Utilities
    qalculate-gtk
    tree
    unzip

    # Neovim is configured in home/default.nix.

    # Assistant.
    claude-code
  ];

  # Brave, de-fanged. Managed policy is the supported way to do this and it
  # survives updates, unlike poking at the profile directory.
  environment.etc."brave/policies/managed/nyx.json".text = builtins.toJSON {
    BraveRewardsDisabled = true;
    BraveWalletDisabled = true;
    BraveVPNDisabled = true;
    BraveAIChatEnabled = false;
    TorDisabled = false;
    MetricsReportingEnabled = false;
    SafeBrowsingExtendedReportingEnabled = false;
    SearchSuggestEnabled = false;
    PasswordManagerEnabled = false; # KeePassXC does this job
    SyncDisabled = true;
    DefaultSearchProviderEnabled = true;
    DefaultSearchProviderName = "DuckDuckGo";
    DefaultSearchProviderSearchURL = "https://duckduckgo.com/?q={searchTerms}";
  };

  # No Google auth broker or geolocation. DNS is Quad9, see security.nix.
  services.gnome.gnome-online-accounts.enable = lib.mkForce false;
  services.geoclue2.enable = lib.mkForce false;
}
