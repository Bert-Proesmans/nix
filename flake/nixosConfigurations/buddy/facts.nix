{ ... }:
{
  # Generated with `head -c4 /dev/urandom | od -A none -t x4`
  # NOTE; The hostId is a marker that prevents ZFS from importing pools coming from another system.
  # It's best practise to mark the pools as 'exported' before moving them between systems.
  # NOTE; Force importing is possible, ofcourse.
  hostId = "525346fb";
  macAddresses."b4:2e:99:15:33:a6".tags = [
    "management"
    "service"
  ];
  domainName = "internal.proesmans.eu";
  tags = [
    "hypervisor"
  ];
  services."192.168.88.11".tags = [
    "dns"
    "webserver"
  ];
  services."100.116.84.29".tags = [ "tailscale" ];
}
