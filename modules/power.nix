{ config, pkgs, lib, ... }:

# Power, battery and suspend.

{
  # ---------------------------------------------------------------------
  # Suspend
  # ---------------------------------------------------------------------
  # S3 rather than s2idle, which drains hard overnight in a bag.
  # Verify with: cat /sys/power/mem_sleep
  boot.kernelParams = [ "mem_sleep_default=deep" ];

  # suspend-then-hibernate needs swap >= RAM; not configured, so plain
  # suspend for now.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "suspend";
  };
  # systemd.sleep.extraConfig = "HibernateDelaySec=2h";
  # services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";

  # ---------------------------------------------------------------------
  # Battery
  # ---------------------------------------------------------------------
  # TLP is configured in hosts/t490/default.nix with charge thresholds.
  # These are the extras that matter on this chassis.
  services.upower.enable = true;
  powerManagement.enable = true;
  powerManagement.powertop.enable = true;   # applies tunables at boot

  # Conflicts with TLP. Explicitly off so nothing pulls it in.
  services.power-profiles-daemon.enable = false;

  # ---------------------------------------------------------------------
  # Idle behaviour
  # ---------------------------------------------------------------------
  # hypridle timings live in home/desktop.nix: dim at 4min, lock at 5,
  # screen off at 6, suspend at 15. Change them there, not here.

  environment.systemPackages = with pkgs; [
    powertop
    acpi
    lm_sensors
  ];
}
