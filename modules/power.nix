{ config, pkgs, lib, ... }:

# Power, battery and suspend for the T490s.
#
# The Hyprland ports floating around are desktop-first and largely ignore
# laptops. This module is where Nyx earns its keep on a ThinkPad.

{
  # ---------------------------------------------------------------------
  # Suspend
  # ---------------------------------------------------------------------
  # The T490s supports S3 ("deep") as well as s2idle. s2idle on this
  # generation drains noticeably in a bag overnight. Force deep sleep.
  #
  # If the BIOS is set to "Windows" sleep mode, deep is unavailable. Check
  # with: cat /sys/power/mem_sleep
  # If it shows [s2idle] only, change Config > Power > Sleep State to Linux
  # in BIOS, then this parameter takes effect.
  boot.kernelParams = [ "mem_sleep_default=deep" ];

  # Suspend on lid close, hibernate if it stays shut for a long time.
  # Requires a swap device at least as large as RAM, so this is commented
  # until you have decided on swap. Plain suspend works without it.
  # logind options moved under `settings.Login` to match systemd's own
  # config keys.
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
  # TLP is configured in hosts/t490s/default.nix with charge thresholds.
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
