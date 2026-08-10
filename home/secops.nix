{ config, pkgs, lib, ... }:

# User-level settings for the secops tooling. The packages are in
# modules/secops.nix; this is the runtime data those tools expect to own.
#
# Several of these fetch template or signature sets at first use. That data
# is deliberately not a build input: it changes daily, it is large, and
# pinning it in the store would mean a rebuild to get current templates.

{
  home.sessionVariables = {
    # nuclei defaults to ~/nuclei-templates, straight in $HOME. Move it
    # somewhere that follows the XDG layout.
    NUCLEI_TEMPLATES_DIR = "${config.home.homeDirectory}/.local/share/nuclei-templates";
  };

  systemd.user.tmpfiles.rules = [
    "d %h/.local/share/nuclei-templates 0755 - - -"
  ];
}
