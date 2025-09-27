# Machine for testing various root filesystems
{
  lib,
  config,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    ./disks.nix
    # ./swap.nix
  ];

  system.stateVersion = lib.trivial.release;
  nixpkgs.hostPlatform = lib.systems.examples.gnu64;
  hardware.enableRedistributableFirmware = false;

  users.mutableUsers = false;
  users.users.root.password = "insecure";

  networking.hostId = "2c7371ce";
  networking.useNetworkd = true;
  # Hyper-V does not emulate PCI devices, so network adapters remain on their ethX names
  # eth0 receives an address by DHCP and provides the default gateway route
  # eth1 gets a stable link-local address for SSH, because Windows goes fucky wucky with
  # the host bridge network adapter and that's sad because IP's and routes won't stick
  # after a reboot.
  systemd.network.links = {
    "10-upstream" = {
      matchConfig.OriginalName = "eth0";
      linkConfig.Alias = "Internet uplink";
      linkConfig.AlternativeName = "main";
    };
    "10-hypervisor-connect" = {
      matchConfig.OriginalName = "eth1";
      linkConfig.Alias = "Link local management";
    };
  };

  systemd.network.networks = {
    "30-upstream" = {
      # ERROR; Don't forget to enable MAC address spoofing on the VM network interface
      # attached to host adapter "Static Net"!
      # ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Applicable if using bridged networking on guest, not if NAT'ing
      matchConfig.Name = "eth0";
      networkConfig.DHCP = "ipv4";
      networkConfig.LinkLocalAddressing = "no";
    };

    "30-hypervisor-connect" = {
      matchConfig.Name = "eth1";
      networkConfig = {
        Address = [
          "169.254.245.211/24"
          "fe80::211/64"
        ];
        LinkLocalAddressing = "no";
      };
    };
  };
}
