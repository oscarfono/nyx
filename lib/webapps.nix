# Web apps as first-class applications.
#
# Brave in --app mode gives a chromeless window with its own WM class, so
# Hyprland treats it as a real application: own icon, own window rules, own
# workspace. home/webapps.nix renders each entry into a .desktop file, so
# they appear in fuzzel alongside native apps.
#
# Add an entry, rebuild, and it is in the launcher. Nothing at runtime reads
# this file.
#
# `class` becomes the WM class (brave-<class>-Default) and must be unique.

{
  claude = {
    name = "Claude";
    url = "https://claude.ai";
    class = "claude.ai__";
    categories = [ "Development" "Utility" ];
  };

  whatsapp = {
    name = "WhatsApp";
    url = "https://web.whatsapp.com";
    class = "web.whatsapp.com__";
    categories = [ "Network" "InstantMessaging" ];
  };

  proton = {
    name = "Proton Mail";
    url = "https://mail.proton.me";
    class = "mail.proton.me__";
    categories = [ "Network" "Email" ];
  };

  github = {
    name = "GitHub";
    url = "https://github.com";
    class = "github.com__";
    categories = [ "Development" ];
  };

  tidal = {
    name = "TIDAL";
    url = "https://listen.tidal.com";
    class = "listen.tidal.com__";
    categories = [ "AudioVideo" "Audio" "Player" ];
  };

  youtube = {
    name = "YouTube";
    url = "https://youtube.com";
    class = "youtube.com__";
    categories = [ "AudioVideo" "Video" ];
  };

  exoscale = {
    name = "Exoscale";
    url = "https://portal.exoscale.com";
    class = "portal.exoscale.com__";
    categories = [ "Development" "Network" ];
  };
}
