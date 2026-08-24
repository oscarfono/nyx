{ config, pkgs, lib, ... }:

# Bluetooth for headphones. Import from hosts/t490s/default.nix.

{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General = {
      # Required for most headphones to expose both A2DP and headset profiles.
      Enable = "Source,Sink,Media,Socket";
      Experimental = true;                 # battery reporting
    };
  };

  services.blueman.enable = true;

  # The applet is the bluetooth indicator: state at a glance, click for the
  # device menu. There is no Waybar bluetooth module, deliberately — one
  # indicator per thing.
  #
  # Nothing starts the applet here, on purpose. The blueman package ships
  # etc/xdg/autostart/blueman.desktop, and uwsm starts that entry as
  # app-blueman@autostart.service. That path supplies the full graphical
  # environment, so the applet finds a display and runs.
  #
  # An earlier version of this file added:
  #
  #   systemd.user.services.blueman-applet.wantedBy =
  #     [ "graphical-session.target" ];
  #
  # That line created a second start path. The package unit carries no
  # [Install] section, so the line alone made the unit start at login. The
  # unit does not import the graphical environment, so GTK3 found no
  # GdkScreen, gtk_icon_theme_get_for_screen returned NULL, and the applet
  # stopped at every boot:
  #
  #   AttributeError: 'NoneType' object has no attribute
  #   'prepend_search_path'
  #
  # The tray icon still worked, because the autostart instance was already
  # running. The only symptom was a failed unit in `systemctl --user
  # --failed`. Do not add the line back. Use the autostart entry.

  # Wireplumber handles the audio side; this makes it prefer high-quality
  # A2DP codecs over the low-bandwidth headset profile when both are offered.
  environment.etc."wireplumber/wireplumber.conf.d/50-bluez.conf".text = ''
    monitor.bluez.properties = {
      bluez5.enable-sbc-xq = true
      bluez5.enable-msbc = true
      bluez5.enable-hw-volume = true
      bluez5.roles = [ hsp_hs hsp_ag hfp_hf hfp_ag a2dp_sink a2dp_source ]
    }
  '';

  environment.systemPackages = with pkgs; [ bluetui ];
}
