{ lib, pkgs, site, ... }:
let
  # The only hosts that LUNA may reach on the internet (blue team, B1).
  # Wise is in the list only when the Wise float can make a transfer.
  wiseHost = if site.wise.sandbox then "api.wise-sandbox.com" else "api.wise.com";
  allowed =
    [ "api.anthropic.com" ]
    ++ lib.optional site.telegram "api.telegram.org"
    ++ lib.optional (lib.elem site.wise.mode [ "draft" "auto" ]) wiseHost;

  # One extended regular expression for each host, matched on the whole name.
  filter = pkgs.writeText "luna-egress-allowlist"
    (lib.concatMapStrings (host: "^${lib.replaceStrings [ "." ] [ "\\." ] host}$\n") allowed);

  proxy = "http://127.0.0.1:8888";
  noInternet = {
    IPAddressDeny = "any";
    IPAddressAllow = "localhost";
  };
in
{
  # The filtering proxy. It refuses each host that is not in the allowlist,
  # and each port but 443. Each refusal goes to the journal (B2 watches it).
  services.tinyproxy = {
    enable = true;
    settings = {
      Listen = "127.0.0.1";
      Port = 8888;
      Allow = "127.0.0.1";
      Filter = filter;
      FilterType = "ere";
      FilterDefaultDeny = true;
      FilterURLs = false;
      ConnectPort = 443;
      DisableViaHeader = true;
      Syslog = true;
      LogLevel = "Connect";
      MaxClients = 50;
    };
  };

  systemd.services.tinyproxy.serviceConfig = {
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    NoNewPrivileges = true;
    CapabilityBoundingSet = "";
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    SystemCallFilter = [ "@system-service" "~@privileged" ];
  };

  # The core goes to the internet through the proxy only. The kernel refuses
  # each other connection, also when an attacker controls the core.
  systemd.services.luna-core = {
    after = [ "tinyproxy.service" ];
    wants = [ "tinyproxy.service" ];
    environment = {
      LUNA_HTTPS_PROXY = proxy;
      # For the Python core, if site.core is "python": httpx reads these.
      HTTPS_PROXY = proxy;
      NO_PROXY = "127.0.0.1,localhost";
    };
    serviceConfig = noInternet;
  };

  # The web app needs no internet at all: PostgreSQL and the core are unix
  # sockets, and the voice servers are on 127.0.0.1.
  systemd.services.luna-web.serviceConfig = noInternet;
}
