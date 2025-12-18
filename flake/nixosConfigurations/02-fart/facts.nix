{ ... }:
{
  hostName = "02-fart";
  domainName = "omega.proesmans.eu";
  encryptedDisks = true;
  tags = [
    "fart"
  ];

  # hardware = {};

  host.global.address = "152.70.63.72";
  host.tailscale.address = "100.97.91.109";
  host.oracle = {
    address = "10.0.84.220";
    fqdn = "02-fart.default.omega.oraclevcn.com";
  };

  ## FREEFORM ##
}
