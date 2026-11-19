# UNBUILT — 19 November 2026. Written in the agent's sandbox, which has no Nix.
# This file has NEVER BEEN EVALUATED. The option names below were taken from
# nixpkgs source and from Synapse's own documentation where they could be read;
# the places where they could not are marked UNVERIFIED in the text and listed
# in hosts/vps/README.md.
#
# The command that settles it, from the T490:
#
#     nixos-rebuild build --flake ~/Projects/nyx#vps
#
{ config, pkgs, lib, username, ... }:

# The hub — the reason the server exists.
#
# Matrix, with the Telegram bridge beside it, on a machine that works while the
# T490 keeps the keys.
#
# =====================================================================
# THE TWO DECISIONS THIS FILE ENCODES, AND WHY
# =====================================================================
#
# 1. server_name IS designandweb.ltd, NOT THE MACHINE'S NAME.
#
#    server_name appears at the end of every user ID and every room address:
#    @coop:designandweb.ltd. It is the ONE value in this file that cannot be
#    changed later — change it and every address anyone has written down becomes
#    a stranger. Everything else here is disposable.
#
#    The desk's recommendation, and the reason: the domain is the company's own
#    identity, so the identifiers read as the company rather than as a server
#    provider; and Synapse's own delegation documentation confirms this is
#    exactly what delegation is for — "retain a server_name of example.com so
#    that user IDs, room aliases, etc continue to look like *:example.com,
#    whilst having federation traffic routed to a different server and/or port".
#    The consequence is that the MACHINE IS MOVABLE: rebuild it in another
#    country, point the DNS at the new address, and not one MXID changes.
#
#    So: the identity is designandweb.ltd, the homeserver is
#    matrix.designandweb.ltd, and the two are joined by a file served from the
#    root domain.
#
# 2. FEDERATION IS OFF, AND SO IS REGISTRATION.
#
#    Federation is the single largest reduction in attack surface available, and
#    nothing here needs to speak to another server. It is off by NOT SERVING IT:
#    the listener below exposes the "client" resource only, so a federation
#    request has nothing to arrive at, and no
#    /.well-known/matrix/server file is served to tell anyone where to look.
#
#    Registration is off, so a server that is found by bots cannot be joined by
#    them. See the procedure section for the one account this machine needs.
#
{
  # =====================================================================
  # The discovery file, as a store path
  # =====================================================================
  # A client reads this when someone logs in with @someone:designandweb.ltd —
  # the MXID names the ROOT domain, and this file says where the homeserver
  # actually is. Its absence is the most common cause of "my client cannot log
  # in" on a self-hosted server, because the address and the machine differ.
  #
  # It is the file that makes the machine movable: change this URL, and the
  # homeserver can live anywhere without an MXID changing.
  wellKnownClient = pkgs.writeText "matrix-client-wellknown.json" ''
    {"m.homeserver":{"base_url":"https://matrix.designandweb.ltd"}}
  '';

  # =====================================================================
  # The homeserver
  # =====================================================================
  services.matrix-synapse = {
    enable = true;

    settings = {
      server_name = "designandweb.ltd";

      # --- the listener: client only. This is the federation switch. -------
      # A federation request arrives on /_matrix/federation/* and finds no
      # resource that serves it. The alternative — setting
      # federation_domain_whitelist to an empty list — is documented too, but
      # this one makes the intent structural rather than a policy the software
      # is asked to enforce.
      listeners = [
        {
          port = 8008;
          bind_addresses = [ "127.0.0.1" ];   # nginx is the only way in
          type = "http";
          tls = false;
          x_forwarded = true;
          resources = [
            { names = [ "client" ]; compress = false; }
          ];
        }
      ];

      # --- who may create an account: nobody -------------------------------
      enable_registration = false;
      # And no CAPTCHA or email flow, because there is no registration to
      # complete. Leaving these unset is deliberate.
      enable_registration_without_verification = false;

      # --- stop asking other servers for keys ------------------------------
      # With federation off there is nobody to ask, and the default behaviour
      # would still reach out to matrix.org. Empty is the documented way to
      # mean "nobody".
      trusted_key_servers = [ ];

      # --- the database: SQLite, deliberately ------------------------------
      # One user, one room, a bridge. Postgres is the scale-up path and it is
      # not free: a second database service, its own backup, its own tuning,
      # and synapse-auto-compressor for its maintenance. The day this box holds
      # a second real user, that is the change to make.
      # UNVERIFIED: this is the current homeserver.yaml shape (name + args).
      # Older versions used a flat `database_path` key. If the build rejects
      # it, that is the alternative.
      database = {
        name = "sqlite3";
        args = {
          database = "/var/lib/matrix-synapse/homeserver.db";
        };
      };

      # --- the login endpoint is where the bots go -------------------------
      # A public Matrix server is credential-stuffed continuously. Synapse has
      # built-in rate limiting and these are the documented knobs; fail2ban in
      # modules/server.nix is the second layer, and neither is sufficient alone.
      # UNVERIFIED: the exact rc_login shape.
      rc_login = {
        address = { per_second = 0.17; burst_count = 3; };
        account = { per_second = 0.17; burst_count = 3; };
        failed_attempts = { per_second = 0.17; burst_count = 3; };
      };

      # --- media is the disk filler and the privacy risk -------------------
      # On a chat server the media repository grows forever and holds whatever
      # anyone pasted. A cap on what may be uploaded, and retention handled on
      # the server rather than left to grow.
      max_upload_size = "10M";
      # UNVERIFIED: the retention keys below are the documented ones, but they
      # interact with the Synapse version and are the first thing to read in
      # the generated homeserver.yaml after the first build.
      media_retention = {
        local_media_lifetime = "90d";
        remote_media_lifetime = "30d";
      };
    };
  };

  # =====================================================================
  # The bridge — Telegram, in the room, as the room's own members
  # =====================================================================
  #
  # WHY THIS IS HERE AT ALL, given the desk argued two hours earlier that a
  # bridge is not needed for the Director's own messages (the agent is on every
  # platform already, with one memory). That argument stands for HIS traffic.
  # This is for OTHER PEOPLE: Sam the tuner, a supplier, a customer, whose
  # accounts live on Telegram. Their messages arrive in the room and the room's
  # history holds them, which is the whole point of a hub.
  #
  # nixpkgs packages this as a first-class module, and — confirmed in the module
  # source — registerToSynapse defaults to true when Synapse is enabled, so the
  # two are wired together without a hand-written appservice registration. That
  # is only possible because he administers this homeserver: an appservice
  # cannot be registered on someone else's server, which is why matrix.org was
  # never going to host this.
  services.mautrix-telegram = {
    enable = true;

    # Secrets never go in `settings` — they would land in the world-readable
    # Nix store (policy 09, rule 3). The bridge's configuration supports
    # environment references, and the values come from a sops file.
    environmentFile = "/run/secrets/mautrix-telegram";

    settings = {
      homeserver = {
        address = "http://localhost:8008";
        domain = "designandweb.ltd";
      };
      appservice = {
        # UNVERIFIED: whether the module supplies these itself when
        # registerToSynapse is true, or whether they must be named here. If the
        # build complains about a missing registration, this is the place.
        id = "telegram";
        bot_username = "telegrambot";
        # The secrets, by reference, from the environmentFile above:
        as_token = "\${MAUTRIX_AS_TOKEN}";
        hs_token = "\${MAUTRIX_HS_TOKEN}";
      };
      bridge = {
        permissions = {
          "@coop:designandweb.ltd" = "admin";
        };
        # He signs in once, from his own account, with his own credentials —
        # the bridge does not get a password from a config file.
        relay = { enabled = false; };
      };
      telegram = {
        # These two are NOT secrets in the same sense (they identify the
        # application, not the session) but they are still not for the store.
        api_id = "\${MAUTRIX_TELEGRAM_API_ID}";
        api_hash = "\${MAUTRIX_TELEGRAM_API_HASH}";
      };
    };
  };

  # =====================================================================
  # The front door
  # =====================================================================
  #
  # Two hostnames, two jobs:
  #
  #   designandweb.ltd          the .well-known file that tells a client where
  #                             the homeserver is, and — later — the company's
  #                             own site. It is the ROOT domain because the
  #                             MXIDs are @user:designandweb.ltd, and a client
  #                             looks up https://<server_name>/.well-known/…
  #                             to find the homeserver.
  #   matrix.designandweb.ltd   the homeserver itself.
  #
  # Policy 09 rule 6 says no SERVICE is reachable on an inbound port and that
  # exposure is through a tunnel or a reverse proxy. This is the reverse proxy:
  # Synapse binds to 127.0.0.1 and only nginx listens. The ports 80 and 443 are
  # the proxy's, and they are the two this machine opens.
  security.acme = {
    acceptTerms = true;
    defaults.email = "cooper@oscarfone.com";
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts = {
      # --- the root domain: the discovery file, and nothing else yet --------
      # The file is a STORE PATH rather than a string assembled out of nginx
      # directives. A discovery file is a real file, and returning JSON from a
      # `return` directive is the kind of cleverness that produces a wrong
      # content-type and an evening of "my client cannot connect".
      "designandweb.ltd" = {
        enableACME = true;
        forceSSL = true;
        locations."= /.well-known/matrix/client" = {
          alias = "${wellKnownClient}";
          extraConfig = ''
            default_type application/json;
            # A client running in a browser fetches this cross-origin; without
            # this header the fetch fails and the client reports a login error.
            add_header Access-Control-Allow-Origin "*" always;
          '';
        };
        # Placeholder for the company's own site, which is not built yet. It is
        # deliberately a plain 200 and not a redirect, so that it cannot be
        # mistaken for the site existing.
        locations."/".return = "200 'Design&Web — the company site is not built yet.'";
      };

      # --- the homeserver ---------------------------------------------------
      "matrix.designandweb.ltd" = {
        enableACME = true;
        forceSSL = true;

        # Synapse's own documentation says a reverse proxy should handle both
        # client and federation traffic, because it saves TLS work in Synapse.
        # Federation is off here, so the client API is all that arrives.
        locations."/" = {
          proxyPass = "http://127.0.0.1:8008";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 12M;   # just above Synapse's own 10M cap,
                                        # so the refusal comes from Synapse
                                        # with a clear error rather than from
                                        # nginx with a 413
          '';
        };

        # No /.well-known/matrix/server is served, deliberately: that file is
        # how other servers are TOLD where to find this one, and the answer
        # here is nobody.
      };
    };
  };

  # =====================================================================
  # What this costs in exposure, and it must be recorded
  # =====================================================================
  # Policy 09 rule 9: every exposure is listed in that policy's register, and
  # an exposure that is not on the list is unaudited. The two below are the
  # ports this machine opens, and both are the reverse proxy rather than a
  # service:
  #
  #   80/tcp   ACME's HTTP-01 challenge, and nothing else. Redirects to 443.
  #   443/tcp  the proxy: matrix.designandweb.ltd → Synapse on 127.0.0.1:8008,
  #            and designandweb.ltd → the discovery file.
  #
  # TO BE ADDED TO policies/09-encryption-and-exposure.org §4 BY THE DESK when
  # this module is first built. It is written here so it cannot be forgotten.
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # =====================================================================
  # THE ONE ACCOUNT THIS MACHINE NEEDS, AND THE ONE OPEN QUESTION
  # =====================================================================
  #
  # Registration is off, so the bot account cannot be made through a client.
  # The documented tool is `register_new_matrix_user`, and it authenticates
  # with a `registration_shared_secret` set in Synapse's configuration.
  #
  # WHICH IS A SECRET, AND SECRETS DO NOT GO IN THIS FILE: anything in
  # `settings` is evaluated at build time and ends up in the world-readable
  # Nix store. So the field is deliberately absent above, and the procedure is
  # one of these — to be chosen by reading the module's own option list, which
  # is the step that settles it:
  #
  #   a. If the module offers a *_file option for the shared secret, use it
  #      with a sops path. FIRST THING TO CHECK.
  #   b. Otherwise: the account is created during a short, deliberate window in
  #      which registration is on. Federation is off, the hostname is not yet
  #      announced, and the window is minutes; then it is turned off and this
  #      file is rebuilt. Ugly, and the alternative above is better.
  #   c. Otherwise: the user is inserted with Synapse's admin API using an
  #      admin access token generated on the machine, never stored in Nix.
  #
  # The command that answers it, on the machine that has Nix:
  #
  #   nixos-option services.matrix-synapse | grep -i secret
  #
  # or the same option list in the nixpkgs source at
  # nixos/modules/services/matrix/synapse.nix.
  #
  # THEN, BEFORE THE SERVER IS WORTH ANYTHING: /var/lib/matrix-synapse holds
  # the SIGNING KEY, and policy 09 rule 5 requires it backed up off the machine
  # — lose it and every client sees a different server at the same address.
  # modules/backup.nix is written for the laptop's paths and does not yet cover
  # this box; that is the next change after this one.
}
