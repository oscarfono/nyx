{ pkgs, lib, ... }:

# The ArtCraft "Crafting Apps", from github.com/storytold. Each app is an
# open-source Rust replacement for one Adobe application:
#
#   photocraft   Photoshop     raster and PSD editor
#   lightcraft   Lightroom     non-destructive photo editor
#   vectorcraft  Illustrator   vector art
#   designcraft  InDesign      page layout
#   pdfcraft     Acrobat       PDF reader and editor
#   filmcraft    Premiere      nonlinear video editor
#   effectcraft  After Effects motion graphics and compositing
#   figcraft     XD / Figma    interface design and prototyping
#   soundcraft   Audition      audio editor and DAW (upstream models it on
#                              Avid Pro Tools)
#
# nixpkgs has none of these apps. This module installs the prebuilt
# linux-x86_64 tarball from each GitHub release. A build from source
# compiles a large Rust workspace for each app. On this machine that takes
# a long time, and upstream makes a release every few days.
#
# The binaries link only libc at load time. winit, wgpu and zbus open the
# windowing, GPU and D-Bus libraries with dlopen when the app starts.
# autoPatchelfHook sets the interpreter. runtimeDependencies puts the
# dlopen libraries on the RUNPATH, because the binaries do not declare them.
#
# To update an app:
#
#   1. Find the new tag on the releases page of the repository.
#   2. Set `version` in lib/craft.nix.
#   3. Get the hex hash of linux-x86_64.tar.gz from SHA256SUMS.txt.
#   4. Run `nix hash convert --hash-algo sha256 --to sri <hex>`.
#   5. Set `hash` in lib/craft.nix to the result.

let
  apps = import ../lib/craft.nix;

  mkCraftApp = pname: { version, hash }:
    pkgs.stdenv.mkDerivation {
      inherit pname version;

      src = pkgs.fetchurl {
        url = "https://github.com/storytold/${pname}/releases/download/v${version}/${pname}-${version}-linux-x86_64.tar.gz";
        inherit hash;
      };

      nativeBuildInputs = [ pkgs.autoPatchelfHook ];
      # filmcraft, effectcraft and soundcraft link ALSA at load time.
      buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.alsa-lib ];

      # lib.getLib, because a bare libva gives the -dev output, and that
      # output has no libva.so.2.
      runtimeDependencies = map lib.getLib (with pkgs; [
        dbus
        libGL
        libva            # filmcraft: VA-API video decode
        libxkbcommon
        vulkan-loader
        wayland
        libx11
        libxcursor
        libxi
        libxrender
        libxcb
      ]);

      dontConfigure = true;
      dontBuild = true;

      # The tarball holds bin/ and share/, with the desktop entry, the
      # icons, the man pages and the shell completions in share/.
      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r bin share $out/
        runHook postInstall
      '';

      meta = {
        homepage = "https://github.com/storytold/${pname}";
        license = with lib.licenses; [ asl20 mit ];
        platforms = [ "x86_64-linux" ];
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        mainProgram = pname;
      };
    };
in
{
  environment.systemPackages = lib.mapAttrsToList mkCraftApp apps;
}
