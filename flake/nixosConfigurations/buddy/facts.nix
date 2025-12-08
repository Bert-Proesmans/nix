{ ... }:
{
  hostName = "buddy";
  domainName = "internal.proesmans.eu";
  encryptedDisks = false;
  tags = [
    "hardware"
    "hypervisor"
  ];

  hardware.lan = {
    address = "b4:2e:99:15:33:a6";
    tags = [
      "management"
      "service"
    ];
  };

  host.lan = {
    address = "192.168.88.11";
    tags = [
      "dns"
      "webproxy"
    ];
  };
  host.tailscale.address = "100.116.84.29";

  service.reverse-proxy = {
    port = 443;
    uri = addr: "https://${addr}";
  };

  service.kanidm = {
    port = 443;
    uri = addr: "https://${addr}";
  };

  service.kanidm-replication = rec {
    port = 8444;
    uri = addr: "repl://${addr}:${toString port}";
  };

  ## FREEFORM ##
  # Generated with `head -c4 /dev/urandom | od -A none -t x4`
  # NOTE; The hostId is a marker that prevents ZFS from importing pools coming from another system.
  # It's best practise to mark the pools as 'exported' before moving them between systems.
  # NOTE; Force importing is possible, ofcourse.
  hostId = "525346fb";
}
