{
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  nixpkgs.hostPlatform = lib.systems.examples.gnu64;
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [ "kvm-amd" ];
  boot.kernelParams = [
    "console=ttyS0,9600" # Required for OCI attached console
    # Allow emergency shell in stage-1-init
    "boot.shell_on_fail" # DEBUG
  ];
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
  ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.editor = false;
  boot.loader.systemd-boot.netbootxyz.enable = true;
  boot.tmp.useTmpfs = false; # Only have 1G RAM
  boot.tmp.cleanOnBoot = true;

  networking.useDHCP = true;
  networking.useNetworkd = true;
}
