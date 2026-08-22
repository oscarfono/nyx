{ config, pkgs, lib, ... }:

# Everything a user actually launches. Opinionated by design.
# Emacs lives in modules/emacs.nix, not here.

let
  # Force-installed browser extensions. Brave and Chromium both read the
  # Chrome policy format, and both use the same Web Store, so one entry
  # serves both policies below.
  #
  # The format is "<extension ID>;<update URL>". Read the ID from the
  # address bar on the Web Store page, or from the directory name under
  # Default/Extensions in the browser profile.
  claudeInChrome =
    "fcoeoabgfenejglbffodgkkbkcdhcgfn;https://clients2.google.com/service/update2/crx";
in
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

    # Chromium, for the Claude extension and for testing a page against
    # stock Chrome behaviour. Brave changes enough to hide a bug.
    chromium

    # Credentials. KeePassXC with a local kdbx, no cloud vendor in the loop.
    keepassxc

    # Graphics and layout. Vector, raster, and page layout, in that order.
    inkscape
    gimp
    scribus

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
    ExtensionInstallForcelist = [ claudeInChrome ];

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

  # Chromium policy. Managed policy is the only declarative way to install
  # an extension: an extension that you add from the Web Store lives in the
  # profile directory, and no rebuild can recreate that extension.
  #
  # CAUTION: a forced extension is not removable from the browser. Delete
  # the entry from claudeInChrome above, then rebuild, to remove the
  # extension from both browsers.
  environment.etc."chromium/policies/managed/nyx.json".text = builtins.toJSON {
    ExtensionInstallForcelist = [ claudeInChrome ];

    # Same posture as the Brave policy above.
    MetricsReportingEnabled = false;
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
