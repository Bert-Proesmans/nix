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
  host.tailscale.address = "100.127.116.49";

  ## FREEFORM ##
}
