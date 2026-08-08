# PLACEHOLDER.
#
# Replace this entire file with the output of, on the target machine:
#
#     sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
#
# Do not hand-write UUIDs. The generated file is the one piece of this repo
# that is legitimately machine-specific.
#
# If you are encrypting the root filesystem, the generated file will already
# contain the boot.initrd.luks.devices entry. Leave it alone, and see
# modules/security.nix for the TPM2 enrolment steps that go alongside it.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  # fileSystems."/" = { device = "/dev/disk/by-uuid/REPLACE-ME"; fsType = "ext4"; };
  # fileSystems."/boot" = { device = "/dev/disk/by-uuid/REPLACE-ME"; fsType = "vfat"; };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
