# Provide external endpoint that reverse proxies local services
{ lib, pkgs, config, ... }: {
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  security.acme.certs."alpha.proesmans.eu" = {
    group = config.services.nginx.group;
  };

  services.nginx = {
    enable = true;
    package = pkgs.nginxMainline;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;
    recommendedProxySettings = true;
    recommendedGzipSettings = true;
    recommendedBrotliSettings = true;

    virtualHosts = {
      "default" = {
        default = true;
        rejectSSL = true;
        locations."/".return = "404";
      };

      "photos.alpha.proesmans.eu" = {
        # Use the generated wildcard certificate, see security.acme.certs.<name>
        useACMEHost = "alpha.proesmans.eu";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.175.0.1:8080";
          proxyWebsockets = true;
        };
      };
    };
  };
}
