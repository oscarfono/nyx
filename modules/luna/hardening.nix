{ lib, site, ... }:
{
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.tcp_syncookies" = 1;
  };

  security.protectKernelImage = true;
  environment.defaultPackages = lib.mkForce [ ];
  services.journald.settings.Journal.SystemMaxUse = "1G";

  # Port 22 is public only during the bootstrap.
  services.fail2ban.enable = site.bootstrap;
}
