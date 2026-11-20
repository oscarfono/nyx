{ lib, site, ... }:
let
  voice = site.voice;
in
{
  # Speech to text. Only 127.0.0.1, so only processes on luna can connect.
  services.wyoming.faster-whisper.servers.luna = {
    enable = true;
    uri = "tcp://127.0.0.1:10300";
    sttLibrary = "faster-whisper";
    model = voice.sttModel;
    language = "en";
    device = "cpu";
    # No mDNS. Zeroconf would advertise the server on the network.
    zeroconf.enable = false;
  };

  # Text to speech. The first start downloads the voice from Hugging Face.
  services.wyoming.piper.servers.luna = {
    enable = true;
    uri = "tcp://127.0.0.1:10200";
    voice = voice.ttsVoice;
    lengthScale = voice.lengthScale;
    zeroconf.enable = false;
  };

  # web.nix gives luna-web the addresses of these two servers.
  systemd.services.luna-web = {
    wants = [ "wyoming-faster-whisper-luna.service" "wyoming-piper-luna.service" ];
    after = [ "wyoming-faster-whisper-luna.service" "wyoming-piper-luna.service" ];
  };
}
