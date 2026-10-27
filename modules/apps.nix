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

  # tidal-hifi, an unofficial Electron client for the Tidal web player.
  #
  # This is the upstream AppImage, and not the nixpkgs package. nixpkgs
  # has 8.1.3 on castlabs Electron 43.0.0. On this machine the renderer of
  # that build stops with SIGTRAP. It cannot make shared memory in
  # /dev/shm, and the window stays grey. 9.0.0 uses castlabs Electron
  # 44.5.1 and shows the player.
  #
  # When nixpkgs gets 9.0.0 or later, delete this block and use
  # pkgs.tidal-hifi.
  #
  # To update: set `version`, then set `hash` to the output of
  # `nix hash file --sri --type sha256 tidal-hifi-<version>.AppImage`.
  tidal-hifi =
    let
      pname = "tidal-hifi";
      version = "9.0.0";
      src = pkgs.fetchurl {
        url = "https://github.com/Mastermindzh/tidal-hifi/releases/download/${version}/tidal-hifi-${version}.AppImage";
        hash = "sha256-3E2/Lj52cOGHk27r9yFOG+xiGNC64MExp7Y3A299RZg=";
      };
      contents = pkgs.appimageTools.extract { inherit pname version src; };
    in
    pkgs.appimageTools.wrapType2 {
      inherit pname version src;
      # The desktop entry and the icon from the AppImage. The desktop entry
      # sets StartupWMClass=tidal-hifi, and home/dock.nix pins that class.
      extraInstallCommands = ''
        install -Dm444 ${contents}/tidal-hifi.desktop -t $out/share/applications
        substituteInPlace $out/share/applications/tidal-hifi.desktop \
          --replace-fail 'Exec=AppRun' 'Exec=tidal-hifi'
        cp -r ${contents}/usr/share/icons $out/share/
      '';
      meta = {
        homepage = "https://github.com/Mastermindzh/tidal-hifi";
        # tidal-hifi is MIT. The bundled castlabs Electron is not free.
        license = with lib.licenses; [ mit unfreeRedistributable ];
        platforms = [ "x86_64-linux" ];
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        mainProgram = "tidal-hifi";
      };
    };
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

      # tidal-hifi carries the castlabs build of Electron. That build has
      # Widevine, the DRM module that Tidal needs for HiFi and Max
      # playback. tidal-hifi itself is MIT. See the package above.
      "tidal-hifi"
    ];

  environment.systemPackages = with pkgs; [
    # Browsers. Brave is the default, Firefox is the escape hatch.
    #
    # --disable-pinch stops the page from zooming while you scroll.
    #
    # The touchpad is a full multitouch device: it reports a slot, a
    # position, an orientation and a pressure for each finger. So libinput
    # detects a pinch, and libinput sends the pinch to the window. A
    # two-finger scroll rarely keeps the fingers at one distance, and
    # libinput reads that change of distance as a pinch. Chromium zooms the
    # page for a pinch, which is why a scroll zooms the page and you then
    # type CTRL+0 to repair the zoom.
    #
    # The flag removes pinch zoom from Brave only. CTRL+PLUS, CTRL+MINUS
    # and CTRL+0 still change the zoom. Scrolling and the 3-finger
    # workspace swipe are untouched, because both are separate gestures.
    (brave.override { commandLineArgs = "--disable-pinch"; })
    firefox

    # Chromium, for the Claude extension and for testing a page against
    # stock Chrome behaviour. Brave changes enough to hide a bug.
    #
    # Same flag as Brave, for the same reason.
    (chromium.override { commandLineArgs = "--disable-pinch"; })

    # Credentials. KeePassXC with a local kdbx, no cloud vendor in the loop.
    keepassxc

    # Graphics and layout. Vector, raster, and page layout, in that order.
    inkscape
    gimp
    scribus

    # Music. An unofficial Electron client for the Tidal web player, with
    # HiFi playback and MPRIS media keys. This is the AppImage from the
    # `let` above. A `let` binding takes precedence over `with pkgs`.
    tidal-hifi

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
