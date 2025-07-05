{ lib, config, ... }: {
  networking.firewall.allowedTCPPorts = [ 443 80 ];

  security.dhparams = {
    enable = true;
    params.nginx = { };
  };

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "bproesmans@hotmail.com";

  services.nginx = {
    enable = true;

    recommendedBrotliSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Nginx sends all the access logs to /var/log/nginx/access.log by default.
    # instead of going to the journal!
    commonHttpConfig = "access_log syslog:server=unix:/dev/log;";

    sslDhparam = config.security.dhparams.params.nginx.path;

    streamConfig = ''
      map $ssl_preread_server_name $upstream {
        # By default, forward to TLS frontend of this nginx instance
        default unix:/run/nginx/https-frontend.sock;
        
        # TODO; Others
      }

      server {
        listen 0.0.0.0:443 proxy_protocol;

        proxy_pass $upstream;
        ssl_preread on;
      }

      server {
        listen [::]:443 proxy_protocol;

        proxy_pass $upstream;
        ssl_preread on;
      }
    '';

    upstreams = {
      # photos-upstream.servers."${config.services.immich.host}:${toString config.services.immich.port}" = { };
      web-cache.servers."unix:/run/varnish/frontend.sock" = { };
    };

    defaultListen = [
      { addr = "unix:/run/nginx/https-frontend.sock"; ssl = true; proxyProtocol = true; }
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];

    virtualHosts = {
      "photos.proesmans.eu" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://web-cache";
          proxyWebsockets = true;
          extraConfig = ''
            # Required for larger uploads to be possible (defaults at 10M)
            client_max_body_size 500M;

            # trust proxy protocol
            set_real_ip_from unix:;
            real_ip_header proxy_protocol;
          '';
        };
      };
    };
  };
}
