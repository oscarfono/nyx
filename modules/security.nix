{ config, pkgs, lib, inputs, username, ... }:

# Hardening. Several of these trade convenience for assurance; read before
# flipping switches.

{
  # ---------------------------------------------------------------------
  # Boot integrity
  # ---------------------------------------------------------------------
  # Secure Boot with our own keys, via lanzaboote. Keys live in
  # /var/lib/sbctl and are backed up on the vault USB.
  #   sudo sbctl status    firmware state
  #   sudo sbctl verify    every boot file must report signed
  # If a kernel or bootloader change leaves something unsigned, do NOT
  # reboot with Secure Boot enforcing.
  #
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  # Required for TPM2 unlock.
  boot.initrd.systemd.enable = true;

  # LUKS lives in hardware-configuration.nix. To add TPM2 unlock, once:
  #   sudo systemd-cryptenroll --tpm2-device=auto \
  #        --tpm2-pcrs=0+2+7+12 /dev/sda2
  # PCR 7 binds to Secure Boot state, so do this AFTER enrolling keys or
  # you will invalidate the enrolment on the next boot.

  # ---------------------------------------------------------------------
  # Kernel and runtime
  # ---------------------------------------------------------------------
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Not linuxPackages_hardened: it lags on patches and breaks virtualisation,
  # for little gain over the sysctls below on a workstation.

  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.yama.ptrace_scope" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.tcp_syncookies" = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "vm.mmap_rnd_bits" = 32;
  };

  boot.blacklistedKernelModules = [
    "firewire-core"
    "thunderbolt"  # DMA attack surface. Remove this line if you use a dock.
  ];

  # Secure Boot tooling. Kept on the system rather than reached for via
  # `nix shell` because `sudo sbctl verify` is worth running after any
  # kernel or bootloader change, and friction means it gets skipped.
  environment.systemPackages = [ pkgs.sbctl ];

  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = true;
  };

  # ---------------------------------------------------------------------
  # Access control
  # ---------------------------------------------------------------------
  security.sudo.enable = false;
  security.sudo-rs.enable = true;   # memory-safe sudo
  security.sudo-rs.execWheelOnly = true;

  security.polkit.enable = true;
  security.pam.services.hyprlock = { };
  security.pam.loginLimits = [
    { domain = "*"; item = "core"; type = "hard"; value = "0"; }
  ];

  # FIDO2 second factor for sudo and login. Plug in a key, then:
  #   nix run nixpkgs#pam_u2f -- ... (see README)
  # security.pam.u2f.enable = true;

  # STAGED. Declarative users are the goal, but mutableUsers = false with no
  # declared password means no way in. Sequence:
  #   1. Install with mutableUsers = true (below), set a password with passwd.
  #   2. Get sops working, put a yescrypt hash in secrets.yaml
  #      (generate with: mkpasswd -m yescrypt).
  #   3. Uncomment hashedPasswordFile, flip mutableUsers to false, rebuild.
  #      Do NOT reboot until you have confirmed you can still su to the user.
  # users.mutableUsers and the password file are set in modules/secrets.nix.

  # ---------------------------------------------------------------------
  # Network
  # ---------------------------------------------------------------------
  networking.networkmanager = {
    enable = true;
    wifi.macAddress = "random";
    ethernet.macAddress = "random";
    dns = "systemd-resolved";
  };

  # DNS.
  #
  # Earlier this was DNSSEC="true" and DNSOverTLS="true", i.e. STRICT mode
  # for both, with Quad9 only as *fallback*. That combination breaks
  # resolution on most real networks: NetworkManager hands resolved the
  # DHCP-provided ISP resolver, resolved then insists on DNS-over-TLS to a
  # server that does not speak it, and every lookup fails. Fallback servers
  # are only consulted when no other DNS is configured, so Quad9 never got a
  # look in.
  #
  # Now: Quad9 is the configured DNS, not the fallback. `Domains = "~."`
  # routes ALL queries there rather than to whatever DHCP offered, so the
  # ISP resolver is never used. DNSOverTLS is opportunistic and DNSSEC is
  # allow-downgrade, which still gets encryption and validation where the
  # server supports it without hard-failing where it does not. Tighten to
  # "true" once you have confirmed it works on the networks you use.
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNS = "9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net";
      FallbackDNS = "1.1.1.1#cloudflare-dns.com";
      Domains = "~.";
      DNSSEC = "allow-downgrade";
      DNSOverTLS = "opportunistic";
      Cache = "yes";
    };
  };

  # Quad9, not 8.8.8.8. No Google, including at layer 7.

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
    logRefusedConnections = false;
  };

  services.openssh = {
    enable = true;
    openFirewall = false;   # on demand only, via a local port knock or manual rule
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
    };
  };

  services.fail2ban.enable = true;

  # ---------------------------------------------------------------------
  # Secrets
  # ---------------------------------------------------------------------
  # See modules/secrets.nix. Kept separate because it is gated on the
  # encrypted file existing, and mixing that conditional in here made the
  # hardening options hard to read.

  # ---------------------------------------------------------------------
  # Auditing
  # ---------------------------------------------------------------------
  security.auditd.enable = true;
  security.audit.enable = true;
  security.audit.rules = [ "-a exit,always -F arch=b64 -S execve" ];

  # ClamAV. No daemon: it holds the whole signature set in memory (~1GB) and
  # on a read-only, hash-verified store the realistic threat is passing an
  # infected file on to someone else, not local infection. Scheduled scans
  # cover that at negligible cost.
  services.clamav = {
    daemon.enable = false;
    updater.enable = true;
  };

  # freshclam fires the instant the machine resumes, before DNS is back, and
  # fails. Wait for the network and retry rather than failing the unit.
  systemd.services.clamav-freshclam = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "60s";
    };
  };

  # Weekly scan of the places untrusted files actually land. Reports only,
  # never removes: a false positive deleting your own file is worse than the
  # malware it was looking for. Results: journalctl -u clamav-scan
  systemd.services.clamav-scan = {
    description = "ClamAV scan of downloads and documents";
    serviceConfig = {
      Type = "oneshot";
      Nice = 19;
      IOSchedulingClass = "idle";
      SuccessExitStatus = [ 1 ];   # 1 means "found something", not "failed"
      ExecStart = "${pkgs.clamav}/bin/clamscan -ri /home/${username}/Downloads /home/${username}/Documents";
    };
  };

  systemd.timers.clamav-scan = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
