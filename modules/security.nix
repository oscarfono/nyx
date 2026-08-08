{ config, pkgs, lib, inputs, ... }:

# The part that distinguishes Nyx from a nice-looking Hyprland config.
# Everything here is deliberate. Read the comments before you flip switches,
# because several of these trade convenience for assurance.

{
  # ---------------------------------------------------------------------
  # Boot integrity
  # ---------------------------------------------------------------------
  # Lanzaboote gives you Secure Boot signed with your own keys instead of
  # Microsoft's. It is left OFF here because enabling it before you have
  # created and enrolled keys will leave you with an unbootable machine.
  #
  # Enrolment, once, on the target box:
  #   sudo nix run nixpkgs#sbctl create-keys
  #   (reboot into firmware, clear existing keys, enter Setup Mode)
  #   sudo nix run nixpkgs#sbctl enroll-keys -- --microsoft
  # Then set the two options below and rebuild.
  #
  # boot.loader.systemd-boot.enable = lib.mkForce false;
  # boot.lanzaboote = {
  #   enable = true;
  #   pkiBundle = "/var/lib/sbctl";
  # };

  # systemd in stage 1 initrd. Required for TPM2 unlock, and a better
  # security posture than the old shell-script initrd regardless.
  boot.initrd.systemd.enable = true;

  # Full disk encryption is configured in hardware-configuration.nix by
  # nixos-generate-config. To add TPM2-backed unlock afterwards, once:
  #   sudo systemd-cryptenroll --tpm2-device=auto \
  #        --tpm2-pcrs=0+2+7+12 /dev/nvme0n1p2
  # PCR 7 binds to Secure Boot state, so do this AFTER enrolling keys or
  # you will invalidate the enrolment on the next boot.

  # ---------------------------------------------------------------------
  # Kernel and runtime
  # ---------------------------------------------------------------------
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Note deliberately NOT using linuxPackages_hardened. It lags on security
  # patches, breaks some virtualisation, and the marginal gain over the
  # sysctls below is small for a workstation. Revisit if this becomes a
  # server profile.

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
  users.mutableUsers = true;
  # users.users.coops.hashedPasswordFile = config.sops.secrets.coops-password.path;

  # ---------------------------------------------------------------------
  # Network
  # ---------------------------------------------------------------------
  networking.networkmanager = {
    enable = true;
    wifi.macAddress = "random";
    ethernet.macAddress = "random";
    dns = "systemd-resolved";
  };

  # resolved options moved under `settings.Resolve`, matching
  # resolved.conf's own key names.
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = "true";
      DNSOverTLS = "true";
      FallbackDNS = [ "9.9.9.9#dns.quad9.net" "149.112.112.112#dns.quad9.net" ];
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
  # sops-nix decrypts at activation time into /run/secrets, never into the
  # world-readable Nix store. Age key derived from the host SSH key.
  # DISABLED until secrets/secrets.yaml actually exists. Nix evaluates the
  # path at build time, so pointing at a missing file fails the whole build.
  # Uncomment together, after you have created the file with sops.
  #
  # sops = {
  #   defaultSopsFile = ../secrets/secrets.yaml;
  #   age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  #   secrets.coops-password = { neededForUsers = true; };
  # };

  # ---------------------------------------------------------------------
  # Auditing
  # ---------------------------------------------------------------------
  security.auditd.enable = true;
  security.audit.enable = true;
  security.audit.rules = [ "-a exit,always -F arch=b64 -S execve" ];

  services.clamav = {
    daemon.enable = false;   # on-demand scanning only, the daemon is heavy
    updater.enable = true;
  };
}
