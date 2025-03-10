{ lib, modulesPath, ... }: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # hardware.cpu = {
  #   amd.updateMicrocode = lib.mkForce false;
  #   intel.updateMicrocode = lib.mkForce false;
  # };

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" ];
  boot.initrd.kernelModules = [ "dm-snapshot" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];
  boot.kernelParams = [ "nohibernate" ];
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.netbootxyz.enable = true; # Allows for troubleshooting (low RAM available)
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = {
    btrfs = lib.mkForce false;
    zfs = lib.mkForce false;
  };

  boot.tmp.useTmpfs = false; # Only have 1G RAM
  boot.tmp.cleanOnBoot = true;

  # Slows down write operations considerably
  nix.settings.auto-optimise-store = lib.mkForce false;

  networking.useDHCP = true;
  networking.interfaces.ens3.useDHCP = true;
  # https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/configuringntpservice.htm#Configuring_the_Oracle_Cloud_Infrastructure_NTP_Service_for_an_Instance
  networking.timeServers = [ "169.254.169.254" ];
}
