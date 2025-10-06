{
  lib,
  modulesPath,
  config,
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
  boot.loader.systemd-boot.netbootxyz.enable = true;
  boot.loader.timeout = 1;
  boot.tmp.useTmpfs = true; # More than enough RAM

  boot.initrd.systemd = {
    enable = true;
    emergencyAccess = false;
    network.wait-online.enable = true;
    network.wait-online.anyInterface = true;
    # Configure interfaces during boot the same as while the host runs.
    network.networks = config.systemd.network.networks;
    network.links = config.systemd.network.links;
  };

  networking.hostId = config.proesmans.facts.self.hostId;
  networking.useDHCP = true;
  networking.useNetworkd = true;

  systemd.shutdownRamfs.enable = false;
}
