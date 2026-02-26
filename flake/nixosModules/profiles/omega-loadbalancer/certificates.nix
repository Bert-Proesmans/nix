{ lib, config, ... }:
{
  sops.secrets.cloudflare-zones-key = { };
  sops.secrets.cloudflare-proesmans-key = { };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "bproesmans@hotmail.com";
      dnsProvider = "cloudflare";
      # WARN; READ on all domains, because reasons .. cloudflare API etc
      credentialFiles."CLOUDFLARE_ZONE_API_TOKEN_FILE" = config.sops.secrets.cloudflare-zones-key.path;
      # WARN; WRITE on proesmans.eu domain
      credentialFiles."CLOUDFLARE_DNS_API_TOKEN_FILE" = config.sops.secrets.cloudflare-proesmans-key.path;

      # ERROR; The system resolver is very likely to implement a split-horizon DNS.
      # NOTE; Lego uses DNS requests within the certificate workflow. It must use an external DNS directly since
      # all verification uses external DNS records.
      dnsResolver = "1.1.1.1:53";
    };

    certs."local-omega-services.proesmans.eu" = {
      # Not wildcard domain because service proxying is split between different machines!
      # REF; https://serverfault.com/a/1015832
      # SEEALSO; servic
      extraDomainNames = lib.mkForce [
        "default.omega.proesmans.eu"
        "status.proesmans.eu"
        "omega.status.proesmans.eu"
      ];
    };

    certs."cache-omega-services.proesmans.eu" = {
      # WARN; Not wildcard domain because service proxying is split between different machines!
      # REF; https://serverfault.com/a/1015832
      # SEEALSO; services.nginx.virtualHosts."default.omega.proesmans.eu"
      extraDomainNames = lib.mkForce [
        "pictures.proesmans.eu"
        "omega.pictures.proesmans.eu"
      ];
    };
  };
}
