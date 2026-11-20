# The host name (luna) and the owner (coops) come from mkHost in flake.nix.
{
  # The MagicDNS suffix of your tailnet. Find it in the Tailscale admin console.
  tailnet = "bumblebee-tuatara.ts.net";

  # The SSH public keys that can log in. Tailscale SSH serves the phone.
  # luna/keys/luna_ed25519.pub is a copy of ~/.ssh/luna_ed25519.pub.
  # The private key stays in ~/.ssh and never goes in the repo.
  sshKeys = [
    (builtins.readFile ../../luna/keys/luna_ed25519.pub)
  ];

  # The Tailscale login of the owner. Only this login can open the web app.
  ownerLogin = "cooper@oscarfono.com";

  # The server clock uses UTC. LUNA uses your time zone for briefs and dates.
  timeZone = "UTC";
  ownerTimeZone = "Australia/Perth";

  # The time of the morning brief, in the owner time zone (HH:MM).
  briefTime = "07:00";

  # Set to true for the install. Set to false after Tailscale works.
  # true opens port 22 to the public internet.
  bootstrap = false;

  # Set to true to send nudges to Telegram. Nudges contain no personal data.
  telegram = false;

  # The core that runs as luna-core: "elixir" (stage E5) or "python".
  # To go back to the Python core, set "python" and run make deploy.
  core = "elixir";

  # CAUTION: keep false until the gate test in "The gate for phase 2" passes.
  # true gives the agent the money tools and starts the Monday money post.
  money = false;

  # The voice of LUNA. Refer to "Voice" in LUNA.org.
  # sttModel: base-int8 is faster, small-int8 is more accurate. Measure on luna.
  # ttsVoice: a Piper voice name. lengthScale above 1.0 speaks slower.
  voice = {
    # base-int8: 1.85 s for 2.7 s of speech on luna. small-int8: 4.4 s.
    sttModel = "base-int8";
    ttsVoice = "en_GB-cori-high";
    lengthScale = 1.0;
  };

  # The Wise float. Refer to "Build: the Wise float" in LUNA.org.
  # WARNING: a payment cannot be undone. Keep mode = "dry-run" until the
  # approval flow works for some weeks. Modes: off, dry-run, draft, auto.
  # draft and auto need the secret wise-api-token. auto needs Wise Business.
  wise = {
    mode = "off";
    sandbox = true;          # api.wise-sandbox.com. Set false for real money.
    profileType = "personal";
    maxPerPayment = 100;     # in the payee currency
    maxPerDay = 200;
    # One entry for each payee. LUNA can pay these payees only.
    # landlord = { recipientId = 12345678; currency = "AUD"; maxPerPayment = 80; };
    payees = { };
  };
}
