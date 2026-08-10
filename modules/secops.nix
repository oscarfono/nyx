{ config, pkgs, lib, username, ... }:

# Security and OSINT tooling. Import from hosts/<host>/default.nix.
#
# Kept separate from devops.nix because the two get used at different times
# and this list is long enough to bury the other one.
#
# Most of these are dual-use. That is the nature of the field: nmap is a
# network inventory tool and a scanner depending on whose network it is.
# Run them against things you own or are engaged to test.
#
# Package names change more often here than elsewhere in nixpkgs, since a
# lot of these are single-maintainer Go tools. If a rebuild fails on a name,
# `nix search nixpkgs <tool>` first rather than assuming it is gone.

{
  environment.systemPackages = with pkgs; [
    # -----------------------------------------------------------------
    # Network discovery and analysis
    # -----------------------------------------------------------------
    nmap
    masscan
    rustscan            # fast port sweep, hands off to nmap for detail
    tcpdump
    termshark           # wireshark's analysis in a terminal
    ngrep
    netcat-gnu
    socat
    iperf3
    mtr
    arp-scan
    tshark

    # -----------------------------------------------------------------
    # DNS and infrastructure recon
    # -----------------------------------------------------------------
    dnsx
    subfinder           # passive subdomain enumeration
    amass               # the thorough one, slow, many sources
    dnsrecon
    massdns
    whois
    doggo
    dig                 # part of bind, but the wrapper is what you want
    fierce

    # -----------------------------------------------------------------
    # HTTP and web surface
    # -----------------------------------------------------------------
    httpx               # probe hosts, titles, status, tech
    nuclei              # templated vulnerability scanning
    ffuf                # content discovery
    gobuster
    whatweb
    wafw00f
    testssl             # TLS configuration audit
    sslscan
    zap                 # OWASP ZAP, the open alternative
    burpsuite           # Community Edition: no scanner, throttled intruder

    # -----------------------------------------------------------------
    # OSINT
    # -----------------------------------------------------------------
    maltego             # graph-based OSINT. Community Edition caps results
                        # at 12 per transform and needs a free account.
    theharvester        # emails, names, subdomains from public sources
    sherlock            # username across social platforms
    holehe              # which sites an email is registered with
    maigret
    exiftool            # metadata in images and documents
    mat2                # and stripping it from your own
    yt-dlp
    ripgrep-all         # grep inside PDFs, archives, docs

    # -----------------------------------------------------------------
    # Secrets and supply chain
    # -----------------------------------------------------------------
    gitleaks            # secrets in git history
    trufflehog
    trivy               # containers, filesystems, repos
    grype               # vulnerability scanning from an SBOM
    syft                # generate the SBOM
    vulnix              # nix store against known CVEs
    lynis               # host audit
    osv-scanner

    # -----------------------------------------------------------------
    # Forensics and file analysis
    # -----------------------------------------------------------------
    binwalk
    foremost
    sleuthkit
    yara
    file
    hexyl               # hex viewer that is actually readable
    radare2

    # -----------------------------------------------------------------
    # Crypto and password work
    # -----------------------------------------------------------------
    hashcat
    john
    hash-identifier
    openssl

    # -----------------------------------------------------------------
    # Exploitation framework
    # -----------------------------------------------------------------
    # metasploit is much slower without a database: module search is
    # uncached and hosts/loot/creds are not persisted between sessions.
    # msfdb assumes a mutable system and does not work on NixOS, so the
    # database is declared below instead.
    metasploit
    step-cli            # certificates without the openssl incantations
    age
    sops

    # -----------------------------------------------------------------
    # Cloud and container posture
    # -----------------------------------------------------------------
    prowler             # AWS/Azure/GCP posture assessment
    kube-bench
    kubesec
    dockle

    # -----------------------------------------------------------------
    # Wireless
    # -----------------------------------------------------------------
    # aircrack-ng needs a card with monitor mode; the T490's Intel AX200
    # does support it. Kismet is the passive alternative.
    aircrack-ng
    kismet
    horst
  ];

  # ---------------------------------------------------------------------
  # Metasploit database
  # ---------------------------------------------------------------------
  # Native postgres rather than a container. On a declarative system the
  # usual container arguments do not apply: the service, the database, the
  # user and the permissions are all in this file, and `nixos-rebuild` is
  # the only thing that can change them. A container would add an image to
  # pin, a volume to back up separately, and a daemon in the path of a tool
  # that only needs a local socket.
  #
  # Containers still earn their place for per-project database versions or
  # anything with state you want to throw away. This has neither.
  #
  # Auth is peer over the unix socket: no password, no listening port, and
  # nothing to put in sops. The database is not reachable from the network.
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "msf" ];
    ensureUsers = [{
      name = username;
      ensureDBOwnership = false;
      ensureClauses.login = true;
    }];
    authentication = lib.mkForce ''
      # TYPE  DATABASE  USER  ADDRESS  METHOD
      local   all       all            peer
      host    all       all   ::1/128  trust
      host    all       all   127.0.0.1/32  trust
    '';
  };

  # PostgreSQL 15+ revokes CREATE on the public schema from ordinary users,
  # so metasploit connects, fails to create its tables, and then errors on
  # every query. ensureDBOwnership only works when database and user names
  # match, which they do not here, so grant it explicitly.
  systemd.services.postgresql.postStart = lib.mkAfter ''
    ${config.services.postgresql.package}/bin/psql -tAc \
      'ALTER DATABASE msf OWNER TO "${username}";' || true
    ${config.services.postgresql.package}/bin/psql -d msf -tAc \
      'ALTER SCHEMA public OWNER TO "${username}";' || true
  '';

  # Wireshark needs group membership to capture without root. The wrapper
  # sets the capability on dumpcap rather than running the GUI privileged.
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  # Add yourself: users.users.<name>.extraGroups = [ "wireshark" ];
}
