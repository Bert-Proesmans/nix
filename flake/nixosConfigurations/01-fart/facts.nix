{ ... }:
{
  hostName = "01-fart";
  domainName = "omega.proesmans.eu";
  encryptedDisks = true;
  tags = [
    "fart"
  ];

  # hardware = {};

  host.global.address = "158.101.202.58";
  host.tailscale.address = "100.127.116.49";
  host.oracle = {
    address = "10.0.84.171";
    fqdn = "01-fart.default.omega.oraclevcn.com";
  };

  ## FREEFORM ##
}
