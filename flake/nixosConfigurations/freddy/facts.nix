{ ... }:
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
  host.oracle = {
    address = "10.0.84.105";
    fqdn = "freddy.default.omega.oraclevcn.com";
  };

  service.reverse-proxy = {
    port = 443;
    uri = addr: "https://${addr}";
  };

  service.crowdsec-lapi = rec {
    port = 10124;
    uri = addr: "http://${addr}:${toString port}";
  };

  service.kanidm = {
    port = 443;
    uri = addr: "https://${addr}";
  };

  service.kanidm-replication = rec {
    port = 8444;
    uri = addr: "repl://${addr}:${toString port}";
  };

  service.mail = rec {
    port = 465;
    uri = addr: "smtps://${addr}:${toString port}";
  };

  ## FREEFORM ##
  # Generated with `head -c4 /dev/urandom | od -A none -t x4`
  hostId = "0a73b940";
}
