{ self, config, ... }:
{
  hostName = "freddy";
  domainName = "omega.proesmans.eu";
  encryptedDisks = true;
  tags = [
    "vps"
  ];

  # hardware = { };

  host.global.address = "141.148.244.144";
  host.tailscale.address = "100.106.207.116";

  service.crowdsec-lapi = rec {
    port = 10124;
    uri = addr: "http://${addr}:${toString port}";
  };

  service.kanidm-replication = rec {
    port = 8444;
    uri = addr: "repl://${addr}:${toString port}";
  };

  ## FREEFORM ##
  # Generated with `head -c4 /dev/urandom | od -A none -t x4`
  hostId = "0a73b940";
}
