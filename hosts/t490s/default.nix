{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/desktop.nix
    ../../modules/apps.nix
    ../../modules/fonts.nix
    ../../modules/power.nix
    ../../modules/emacs.nix
    ../../modules/devops.nix
    ../../modules/security.nix
  ];

  networking.hostName = "beta";

  # systemd-boot for now. Swap to lanzaboote once you have enrolled your own
  # Secure Boot keys, see modules/security.nix.
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # T490s specifics. The nixos-hardware module handles most of it, this is
  # the extra that is worth having on this chassis.
  services.thermald.enable = true;
  services.fwupd.enable = true;
  hardware.enableRedistributableFirmware = true;

  # Intel graphics. Yes, it is Intel. We knew what we signed up for.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # Battery longevity on a second-hand machine matters more than peak clocks.
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 85;
    };
  };

  users.users.coops = {
    isNormalUser = true;
    description = "Coops";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "docker" ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = lib.mkDefault true;

  # ---------------------------------------------------------------------
  # VM variant
  # ---------------------------------------------------------------------
  # Applies ONLY to `nixos-rebuild build-vm` / the system.build.vm output.
  # Never reaches real hardware, so a throwaway password here does not
  # weaken the installed system.
  virtualisation.vmVariant = {
    # `password`, not `initialPassword`. initialPassword only takes effect
    # when the account is first created, so it silently does nothing if a
    # nixos.qcow2 from an earlier run is still lying around. `password` is
    # reapplied on every activation.
    users.users.coops.password = "nyx";
    users.users.root.password = "nyx";

    # If home-manager fails, none of our config applies and you fall back to
    # Hyprland's built-in defaults, whose only terminal bind is SUPER+Q ->
    # kitty. Ship kitty in the VM so there is always a way in to read logs.
    environment.systemPackages = [ pkgs.kitty ];

    virtualisation = {
      memorySize = 4096;
      cores = 4;
      resolution = { x = 1600; y = 900; };
      # No custom -display or virtio-vga-gl here. Host-side GL passthrough
      # needs a GTK context with DMABUF, which a Wayland session does not
      # reliably provide, and qemu aborts rather than falling back. The
      # default display works; software rendering makes Hyprland sluggish in
      # the VM but that says nothing about performance on real hardware.
    };
  };

  time.timeZone = "Australia/Perth";
  i18n.defaultLocale = "en_AU.UTF-8";
  console.keyMap = "us";

  # Do not change this after the first build. It is a compatibility marker,
  # not a version number.
  system.stateVersion = "26.05";
}
