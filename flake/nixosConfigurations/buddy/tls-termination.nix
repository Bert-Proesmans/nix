{ pkgs, ... }: {
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  services.nginx = {
    enable = true;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;
    recommendedProxySettings = true;
    recommendedGzipSettings = true;
    recommendedBrotliSettings = true;

    # DEBUG; Log to stderr from debug upwards
    # logError = "stderr debug";

    # Snoop all connections and;
    #
    # - Either terminate on host
    # - Forward special connections as-is upstream
    streamConfig =
      let
        kanidmName = lib.removePrefix "https://" config.services.kanidm.serverSettings.origin;
        kanidmUpstream = config.services.kanidm.serverSettings.bindaddress;
      in
      ''
        map $ssl_preread_server_name $upstream {
          # By default, forward to TLS frontend of this nginx instance
          default unix:/run/nginx/https-frontend.sock;
          
          # Kanidm performs its own TLS termination
          ${kanidmName} ${kanidmUpstream};
        }

        server {
          listen 0.0.0.0:443;

          proxy_pass $upstream;
          ssl_preread on;
        }

        server {
          listen [::]:443;

          proxy_pass $upstream;
          ssl_preread on;
        }
      '';

    # All configuration below is specific to the http module!
    # eg "upstreams" can be configured within http block, but also stream block etc

    upstreams = {
      photos-upstream.servers."unix:/run/nginx/does-not-exist.vsock" = { };
    };

    defaultListen = [
      { addr = "unix:/run/nginx/https-frontend.sock"; ssl = true; }
      { addr = "0.0.0.0"; port = 80; ssl = false; }
    ];

    virtualHosts = {
      "photos.alpha.proesmans.eu" = {
        # Use the generated wildcard certificate, see security.acme.certs.<name>
        useACMEHost = "alpha.proesmans.eu";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://photos-upstream";
          proxyWebsockets = true;
          extraConfig = ''
            # Required for larger uploads to be possible (defaults at 10M)
            client_max_body_size 500M;
          '';
        };
      };
    };
  };
}
