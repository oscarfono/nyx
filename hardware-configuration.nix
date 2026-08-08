# PLACEHOLDER — replace on the target machine with:
#
#     sudo nixos-generate-config --show-hardware-config > hosts/t490s/hardware-configuration.nix
#
# The filesystem entries below are stubs that match the labels used in the
# install steps (nixos, BOOT), purely so `nix flake check` can evaluate on a
# machine that is not the target. They are NOT your real disk layout. The
# generated file will carry the correct UUIDs and, if you encrypted the root,
# the boot.initrd.luks.devices entry as well.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
