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
