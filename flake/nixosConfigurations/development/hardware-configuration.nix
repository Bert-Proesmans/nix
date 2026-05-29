{ lib, ... }:
{
  # Define the platform type of the target configuration
  nixpkgs.hostPlatform = lib.systems.examples.gnu64;
  # WARN; Don't actually need to cross-compile for aarch64. Choose to remote build the closures!
  # Nixos-anywhere supports remote build, also nixos-rebuild supports(?) remote build.
  # boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Enables (nested) virtualization through hardware acceleration.
  # There is no harm in having both modules loaded at the same time, also no real overhead.
  boot.kernelModules = [
    "kvm-amd"
    "kvm-intel"
  ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.editor = false;

  # Generated with `head -c4 /dev/urandom | od -A none -t x4`
  # NOTE; The hostId is a marker that prevents ZFS from importing pools coming from another system.
  # It's best practise to mark the pools as 'exported' before moving them between systems.
  # NOTE; Force importing is possible, ofcourse.
  networking.hostId = "9c522fc1";

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
   systemd.network.networks = {
    "eth0-management" = {
      matchConfig.Name = "eth0";
      DHCP = "yes";
      # NOTE; Address configuration matches VM configuration!
      address = [
        "172.27.224.139/24"
        "fde0:5584:ba8e::139/64"
      ];
      gateway = [
        "172.27.224.1"
        "fde0:5584:ba8e::1"
      ];
    };
  };
}
