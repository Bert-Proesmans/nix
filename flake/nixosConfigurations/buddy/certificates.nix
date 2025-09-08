# Setup automatic (ACME) certificate renewal for proesmans domains
{ lib, config, ... }:
{
  sops.secrets.cloudflare-proesmans-key = { };
  sops.secrets.cloudflare-zones-key = { };

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

    certs."alpha.idm.proesmans.eu" = {
      domain = lib.mkForce "alpha.idm.proesmans.eu";
      # NOTE; Certificate split to limit eavesdropping by proxy
      extraDomainNames = lib.mkForce [
        "idm.proesmans.eu"
      ];
    };

    certs."alpha.proesmans.eu" = {
      # This block requests a wildcard certificate.
      domain = lib.mkForce "*.alpha.proesmans.eu";
      extraDomainNames = lib.mkForce [
        "pictures.proesmans.eu"
        "alpha.pictures.proesmans.eu"
        "passwords.proesmans.eu"
        "alpha.passwords.proesmans.eu"
        "wiki.proesmans.eu"
        "alpha.wiki.proesmans.eu"
      ];
    };
  };
}
