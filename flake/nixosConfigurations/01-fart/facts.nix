{ ... }:
{
  ipAddress = "158.101.202.58";
  # IPv6 not handled currently
  domainName = "omega.proesmans.eu";
  tags = [
    "fart"
  ];
  encryptedDisks = true;
  services."100.127.116.49".tags = [ "tailscale" ];
}
