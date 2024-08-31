{ lib, ... }: {
  # Define the platform type of the target configuration
  nixpkgs.hostPlatform = lib.systems.examples.gnu64;

  # Enables (nested) virtualization through hardware acceleration.
  # There is no harm in having both modules loaded at the same time, also no real overhead.
  boot.kernelModules = [ "kvm-amd" "kvm-intel" ];

  # Generated with `head -c4 /dev/urandom | od -A none -t x4`
  # NOTE; The hostId is a marker that prevents ZFS from importing pools coming from another system.
  # It's best practise to mark the pools as 'exported' before moving them between systems.
  # NOTE; Force importing is possible, ofcourse.
  networking.hostId = "9c522fc1";

  boot.supportedFilesystems = [ "zfs" ]; # enables zfs

  # Load Hyper-V kernel modules
  virtualisation.hypervGuest.enable = true;

  # Use networkd instead of the pile of shell scripts
  networking.useNetworkd = true;
  networking.useDHCP = false;
  # WARN; Don't wait for online, it slows boots and rebuilds
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.network.wait-online.enable = false;

  # Do not take down the network for too long when upgrading,
  # This also prevents failures of services that are restarted instead of stopped.
  # It will use `systemctl restart` rather than stopping + delayed start;
  # `systemctl stop` followed by `systemctl start`
  systemd.services.systemd-networkd.stopIfChanged = false;
  # Services that are only restarted might be not able to resolve when resolved is stopped before
  systemd.services.systemd-resolved.stopIfChanged = false;

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
        Address = [ "169.254.245.139/24" "fe80::139/64" ];
        LinkLocalAddressing = "no";
      };
    };
  };
}
