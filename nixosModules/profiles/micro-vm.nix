# Lambda
{ commonNixosModules }:
# NixOS Module
{ lib, ... }: {
  # Importing the common nixos modules to allow for uniform declarative host configuration between
  # nixos hosts and microVMs.
  imports = commonNixosModules;

  # Generate a nixos module with for each defined vm containing all hypervisor
  # relevant option values.
  microvm.hypervisor = lib.mkForce "qemu";

  microvm.vcpu = lib.mkDefault 1;
  microvm.mem = lib.mkDefault 512;
  # Allow the VM to use an additional 512 MB at boot, reclaimed by the host after settling
  microvm.balloonMem = lib.mkDefault 512;
  microvm.graphics.enable = false;

  # Overwrite default root filesystem minimizing ram usage.
  # NOTE; All required files for boot and configuration are within the /nix mount!
  # What's left are temporary files, application logs and -artifacts, and to-persist application data.
  # TODO; Do I need to configure /tmp ?
  fileSystems."/" = {
    device = "rootfs";
    fsType = "tmpfs";
    options = [ "size=10%,mode=0755" ];
    neededForBoot = true;
  };

  # It is highly recommended to share the host's nix-store
  # with the VMs to prevent building huge images.
  microvm.shares = [{
    source = "/nix/store";
    mountPoint = "/nix/.ro-store";
    tag = "ro-store";
    proto = "virtiofs";
    # NOTE; Hugetables backed mapping isn't enabled in microvm.nix.
    # - The ZFS compatible kernel has compiled in support
    # - The hugetblfs is not mounted by default
    #   SEEALSO; `nixosModules.profiles.hypervisor`
    # - The qemu VM's are not started making use of hugetables
    #   REF; https://github.com/astro/microvm.nix/blob/ac28e21ac336dbe01b1f1bcab01fd31db3855e40/lib/runners/qemu.nix#L210C20-L210C40
    # ERROR; The parameter below is only used for p9 sharing. This is _not_ the same as virtiofs' accessmode!
    # securityModel = "mapped";
  }];

  networking.useNetworkd = true;
  systemd.network.networks."20-lan" = {
    matchConfig.Type = "ether";
    networkConfig = {
      Address = [ "192.168.100.3/24" ];
      Gateway = "192.168.100.1";
      DHCP = "ipv4";
      IPv6AcceptRA = false;
    };
  };
  # Required for docker-in-vm
  # systemd.network.networks."19-docker" = {
  #   matchConfig.Name = "veth*";
  #   linkConfig = {
  #     Unmanaged = true;
  #   };
  # };

  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [
      "systemd-journal" # Read the systemd service journal
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
    ];
  };

  # Allow for remote management
  services.openssh.enable = true;

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "23.11";
}
