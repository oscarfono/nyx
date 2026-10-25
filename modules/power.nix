{ config, pkgs, lib, ... }:

# Power, battery and suspend.

{
  # ---------------------------------------------------------------------
  # Suspend
  # ---------------------------------------------------------------------
  # S3 rather than s2idle, which drains hard overnight in a bag.
  # Verify with: cat /sys/power/mem_sleep
  boot.kernelParams = [ "mem_sleep_default=deep" ];

  # ---------------------------------------------------------------------
  # Swap
  # ---------------------------------------------------------------------
  # zram is compressed swap in RAM. This machine had no swap of any kind,
  # so a process that asked for the last of the 16GB met the OOM killer
  # with no warning. The emacs daemon reached 1.7GB during the native
  # recompile for emacs 31, which shows the headroom is not theoretical.
  #
  # zram gives that headroom without a disk partition, so zram changes
  # nothing about LUKS and nothing about the boot path.
  #
  # zram does NOT make hibernate possible. Hibernate needs a DISK swap area
  # that is at least the size of RAM, and the kernel needs a `resume=`
  # parameter that points at the swap area. On this machine the swap area
  # would sit inside the LUKS container, so the initrd must open the
  # container before the initrd resumes. That change belongs in its own
  # generation, with a live USB at hand.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # suspend-then-hibernate needs a disk swap area >= RAM; see the zram note
  # above for why this machine has none. Plain suspend for now.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "suspend";
  };
  # systemd.sleep.extraConfig = "HibernateDelaySec=2h";
  # services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";

  # ---------------------------------------------------------------------
  # Spurious wake from S3
  # ---------------------------------------------------------------------
  # This chassis leaves S3 in the same second that it enters S3, because a
  # wake event is asserted at entry. The kernel log shows the symptom:
  #
  #   PM: Preparing to enter system sleep state S3
  #   PM: Low-level resume complete          <- same second
  #
  # hypridle then suspends again 15 minutes later, so the machine never
  # sleeps. In September 2026 this ran for 13 days: 103 suspend attempts,
  # each about 10 seconds. The machine was in a closed bag for several days
  # of that time, and the heat killed the panel backlight.
  #
  # The USB controller (XHC) is the usual source on this chassis. Use
  # nyx-wake-probe to confirm the source if the symptom comes back.
  #
  # A write to /proc/acpi/wakeup TOGGLES the device, so the unit must read
  # the current state first. A second write would enable the device again.
  systemd.services.nyx-disable-usb-wakeup = {
    description = "Disable the USB controller as a system wake source";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      state=$(${pkgs.gawk}/bin/awk '$1 == "XHC" { print $3 }' /proc/acpi/wakeup)
      case "$state" in
        *enabled*)
          echo XHC > /proc/acpi/wakeup
          echo "disabled XHC as a wake source"
          ;;
        *)
          echo "XHC is already disabled, state=$state"
          ;;
      esac
    '';
  };

  # ---------------------------------------------------------------------
  # Suspend watchdog
  # ---------------------------------------------------------------------
  # The wake-source fix above treats the known cause. This watchdog limits
  # the damage from any other cause.
  #
  # A suspend that returns in less than 30 seconds did not work. After 3 of
  # these in a row, with the lid closed and no mains power, the machine is
  # in a bag and nobody can see it. The watchdog powers the machine off,
  # because a clean shutdown is better than days at full power with no
  # airflow.
  #
  # The watchdog does NOT act while the lid is open, and it does NOT act on
  # mains power. An unattended run with the lid open is safe from it.
  powerManagement.powerDownCommands = ''
    ${pkgs.coreutils}/bin/mkdir -p /run/nyx
    ${pkgs.coreutils}/bin/date +%s > /run/nyx/suspend-start
  '';

  powerManagement.resumeCommands = ''
    ${pkgs.coreutils}/bin/mkdir -p /run/nyx
    start=$(${pkgs.coreutils}/bin/cat /run/nyx/suspend-start 2>/dev/null || echo 0)
    now=$(${pkgs.coreutils}/bin/date +%s)
    slept=$(( now - start ))
    fails=$(${pkgs.coreutils}/bin/cat /run/nyx/suspend-fails 2>/dev/null || echo 0)

    if [ "$start" -gt 0 ] && [ "$slept" -lt 30 ]; then
      fails=$(( fails + 1 ))
    else
      fails=0
    fi
    echo "$fails" > /run/nyx/suspend-fails
    echo "nyx suspend watchdog: slept ''${slept}s, short suspends in a row: $fails"

    if [ "$fails" -ge 3 ]; then
      lid=$(${pkgs.gawk}/bin/awk '{ print $2 }' /proc/acpi/button/lid/LID/state 2>/dev/null)
      ac=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/AC/online 2>/dev/null || echo 1)
      if [ "$lid" = "closed" ] && [ "$ac" = "0" ]; then
        echo "nyx suspend watchdog: suspend does not work, lid closed, on battery. Powering off."
        ${pkgs.systemd}/bin/systemctl poweroff
      fi
    fi
  '';

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

    # Finds the device that wakes the machine from S3. Run it as root:
    #   sudo nyx-wake-probe
    #
    # The script suspends the machine, so close your work first. Press the
    # power button to wake the machine if the suspend works.
    (writeShellScriptBin "nyx-wake-probe" ''
      set -u
      if [ "$(${pkgs.coreutils}/bin/id -u)" != "0" ]; then
        echo "Run this script as root." >&2
        exit 1
      fi

      SRC=/sys/kernel/debug/wakeup_sources

      echo "=== armed ACPI wake sources ==="
      ${pkgs.gnugrep}/bin/grep -E "enabled" /proc/acpi/wakeup || true

      if [ ! -r "$SRC" ]; then
        echo "$SRC is not readable, so per-device counts are not available."
        exit 1
      fi

      echo
      echo "=== wake event counts before the suspend ==="
      ${pkgs.gawk}/bin/awk 'NR==1 || $3 > 0 { print $1, "events="$3 }' "$SRC"

      echo
      echo "Suspending in 5 seconds. Wake the machine with the power button."
      ${pkgs.coreutils}/bin/sleep 5
      before=$(${pkgs.coreutils}/bin/date +%s)
      ${pkgs.systemd}/bin/systemctl suspend
      ${pkgs.coreutils}/bin/sleep 8
      after=$(${pkgs.coreutils}/bin/date +%s)

      echo
      echo "=== result ==="
      echo "The machine was away for $(( after - before )) seconds."
      echo "A value near 8 means the suspend failed."
      echo
      echo "=== wake event counts after the suspend ==="
      echo "The device with a raised count is the device that wakes the machine."
      ${pkgs.gawk}/bin/awk 'NR==1 || $3 > 0 { print $1, "events="$3 }' "$SRC"
    '')
  ];
}
