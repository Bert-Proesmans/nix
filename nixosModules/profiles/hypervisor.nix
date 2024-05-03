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

  # Attach all virtual ethernet interfaces to the bridge!
  systemd.network.networks."31-microvm-interfaces" = {
    matchConfig.Name = "vm-* tap-*";
    networkConfig.Bridge = "bridge0";
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = lib.mkForce "1";
    "net.ipv6.conf.all.forwarding" = lib.mkForce "1";
    "net.ipv6.conf.default.forwarding" = lib.mkForce "1";
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
