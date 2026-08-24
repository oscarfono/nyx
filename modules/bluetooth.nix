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
  systemd.user.services.blueman-applet = {
    wantedBy = [ "graphical-session.target" ];

    # blueman-applet is GTK3 and it calls gtk_icon_theme_get_for_screen at
    # start. That call needs a GdkScreen. A pure Wayland GTK3 process has
    # no GdkScreen, so the call returns NULL and the applet stops:
    #
    #   AttributeError: 'NoneType' object has no attribute
    #   'prepend_search_path'
    #
    # GDK_BACKEND=x11 sends the applet through Xwayland, which supplies a
    # GdkScreen. The tray icon is a small X11 client. Everything else in
    # the session stays on Wayland.
    environment.GDK_BACKEND = "x11";
  };

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
