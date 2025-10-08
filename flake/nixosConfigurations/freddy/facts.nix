{ ... }:
{
  # Generated with `head -c4 /dev/urandom | od -A none -t x4`
  hostId = "0a73b940";
  ipAddress = "141.148.244.144";
  # IPv6 not handled currently
  domainName = "omega.proesmans.eu";
  tags = [
    "vps"
  ];
  encryptedDisks = true;
  services."100.106.207.116".tags = [ "tailscale" ];
}
