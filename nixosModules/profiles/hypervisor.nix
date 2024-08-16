{ inputs }:
let
  microvm-host-module = inputs.microvm.nixosModules.host;
in
{ lib, ... }: {
  imports = [ microvm-host-module ];

  microvm.host.enable = lib.mkDefault false;
  microvm.autostart = [ ];

  # The hypervisor infrastructure is ran by the systemd framework
  networking.useNetworkd = true;

  # Build a bridge!
  systemd.network.netdevs."bridge0" = {
    netdevConfig = {
      Name = "bridge0";
      Kind = "bridge";
    };
  };

  systemd.network.networks."30-link-local-bridge" = {
    matchConfig.Name = "bridge0";
    networkConfig = {
      DHCPServer = true;
      IPv6SendRA = true;
    };
    addresses = [
      {
        # Random stable IPv4
        Address = "10.185.165.236/24";
      }
      {
        # Random stable IPv6
        Address = "fd42:d5a4:b5e7::2d7c:b5bb:9ee1:edae/64";
      }
      {
        # Random stable IPv6. Used for connecting to VM's over network
        #
        # REF; https://github.com/astro/microvm.nix/issues/123
        #
        # ERROR; Address is set on the bridge because the TAP won't send neighbour advertisements
        # for its own address. The bridge _does_. So it's either intentional to do something with
        # enslaved TAP, or the bridge config is wrong and filtering out these control packets :/
        Address = "fe81::2d7c:b5bb:9ee1:edae/64";
      }
    ];
    ipv6Prefixes = [{
      # Site-local prefix generated through https://www.unique-local-ipv6.com
      Prefix = "fd42:d5a4:b5e7::/64";
    }];
  };
  # WARN; Allow incoming DHCP requests on the bridge interface
  networking.firewall.interfaces."bridge0".allowedUDPPorts = [ 67 ];

  # Attach all virtual ethernet interfaces to the bridge!
  systemd.network.networks."31-microvm-interfaces" = {
    matchConfig.Name = "vm-* tap-*";
    networkConfig.Bridge = "bridge0";

    #addresses = [{
    # Random stable IPv6. Used for connecting to VM's over network
    #
    # REF; https://github.com/astro/microvm.nix/issues/123
    #
    # ERROR; Doesn't work; the TAP interface becomes unresponsive to any control protocol
    # packets when enslaved in a bridge. Need to set the address on the bridge instead!
    # addressConfig.Address = "fe81::2d7c:b5bb:9ee1:edae/64";
    #}];
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = "1";
    "net.ipv6.conf.all.forwarding" = "1";
    "net.ipv6.conf.default.forwarding" = "1";
  };

  # mount /hugetlbfs for virtio/qemu
  # systemd.mounts = [{
  #   where = "/hugetlbfs";
  #   enable = true;
  #   what = "hugetlbfs";
  #   type = "hugetlbfs";
  #   options = "pagesize=2M";
  #   requiredBy = [ "basic.target" ];
  # }];
}
