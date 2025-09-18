{
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  nixpkgs.hostPlatform = lib.systems.examples.aarch64-multiplatform;
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [ ];
  boot.kernelParams = [
    "console=ttyS0,9600" # Required for OCI attached console
    # Allow emergency shell in stage-1-init
    "boot.shell_on_fail" # DEBUG
  ];
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
    "usbhid"
  ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.editor = false;
  boot.tmp.useTmpfs = false; # Only have 1G RAM
  boot.tmp.cleanOnBoot = true;

  networking.useDHCP = true;
  networking.useNetworkd = true;
}
