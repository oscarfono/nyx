{ config, pkgs, lib, ... }:

# Everything a user actually launches. Opinionated by design.
# Emacs lives in modules/emacs.nix, not here.

{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "brave"
      "claude-code"
    ];

  environment.systemPackages = with pkgs; [
    # Browsers. Brave is the default, Firefox is the escape hatch.
    brave
    firefox

    # Credentials. KeePassXC with a local kdbx, no cloud vendor in the loop.
    keepassxc

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

  # No Google. A statement of intent, but also enforced:
  # no chrome, no chromium, no Google auth broker, no Google DNS (see
  # modules/security.nix).
  services.gnome.gnome-online-accounts.enable = lib.mkForce false;
  services.geoclue2.enable = lib.mkForce false;
}
