{ lib, pkgs, config, ... }: {

  proesmans.vsock-proxy.proxies = [
    {
      # Setup http-server on 127.0.0.1:9585
      # <- receives from listening VSOCK
      # <- receives packet from guest VM
      listen.vsock.cid = 2;
      listen.port = 8080;
      transmit.tcp.ip = "127.0.0.1";
      transmit.port = 9585;
    }
  ];

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "bproesmans@hotmail.com";
      dnsProvider = "cloudflare";
      credentialFiles."CLOUDFLARE_DNS_API_TOKEN_FILE" = "/aaa/not-exist";
      credentialFiles."CLOUDFLARE_ZONE_API_TOKEN_FILE" = "/bbb/not-exist";

      # ERROR; The system resolver is very likely to implement a split-horizon DNS.
      # NOTE; Lego uses DNS requests within the certificate workflow. It must use an external DNS directly since
      # all verification uses external DNS records.
      dnsResolver = "1.1.1.1:53";
    };

    certs."alpha.proesmans.eu" = {
      # This block requests a wildcard certificate.
      domain = "*.alpha.proesmans.eu";
      group = "nginx";
    };
  };

  systemd.services.nginx.unsock = {
    enable = true;
    ip-scope = "127.175.0.0/32";
    proxies = [
      {
        match.port = 8000;
        to.vsock.cid = 3000;
        to.vsock.port = 8080;
      }
      {
        match.port = 8010;
        to.vsock.cid = 3001;
        to.vsock.port = 8080;
      }
    ];
  };

  services.nginx = {
    enable = true;
    package = pkgs.unsock.wrap pkgs.nginxMainline;

    virtualHosts = {
      "photos.alpha.proesmans.eu" = {
        useACMEHost = "alpha.proesmans.eu";
        listen = [
          { addr = "unix:/run/nginx/https-frontend.sock"; ssl = true; }
          {
            # NOTE; This attribute set is used for the non-ssl redirect stanza
            addr = "0.0.0.0";
            port = 80;
            ssl = false;
          }
        ];
        forceSSL = true;
        locations."/".proxyPass = "http://127.0.0.1:8000";
      };

      "testing.alpha.proesmans.eu" = {
        useACMEHost = "alpha.proesmans.eu";
        listen = [
          { addr = "unix:/run/nginx/https-frontend.sock"; ssl = true; }
          {
            # NOTE; This attribute set is used for the non-ssl redirect stanza
            addr = "0.0.0.0";
            port = 80;
            ssl = false;
          }
        ];
        forceSSL = true;
        locations."/".proxyPass = "http://127.0.0.1:12000";
      };
    };

    streamConfig = ''
      upstream https-frontend {
          server unix:/run/nginx/https-frontend.sock;
      }

      upstream sso {
          server 127.175.0.0:8040;
      }

      map $ssl_preread_server_name $upstream {
        default https-frontend;
        alpha.idm.proesmans.eu sso;
      }
      
      server {
        listen 0.0.0.0:443;

        proxy_pass $upstream;
        ssl_preread on;
      }
    '';
  };

}
