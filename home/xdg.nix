{ config, pkgs, lib, ... }:

# Default applications. Without these, "open this link" and "open this PDF"
# land wherever the desktop portal guesses, which on a fresh NixOS is often
# nowhere at all.

let
  browser = [ "brave-browser.desktop" ];
  editor  = [ "emacsclient.desktop" ];
  images  = [ "imv.desktop" ];
  video   = [ "mpv.desktop" ];
  files   = [ "org.gnome.Nautilus.desktop" ];
in
{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = browser;
      "x-scheme-handler/http" = browser;
      "x-scheme-handler/https" = browser;
      "x-scheme-handler/about" = browser;
      "x-scheme-handler/unknown" = browser;

      "application/pdf" = browser;   # Brave's viewer is fine and always there

      "text/plain" = editor;
      "text/markdown" = editor;
      "application/json" = editor;
      "application/x-shellscript" = editor;

      "image/png" = images;
      "image/jpeg" = images;
      "image/gif" = images;
      "image/webp" = images;
      "image/svg+xml" = browser;

      "video/mp4" = video;
      "video/x-matroska" = video;
      "video/webm" = video;
      "audio/mpeg" = video;
      "audio/flac" = video;

      "inode/directory" = files;
    };
  };

  xdg.userDirs = {
    enable = true;
    createDirectories = true;
  };
}
