{ lib, config, ... }:
{
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # Must be member of cert-group to get access to the certs
  # NOTE; root also required because that's the service user for nginx-config-reload.
  users.groups.alpha-certs.members = [
    "root"
    "nginx"
  ];

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
    # - Either terminate on host (immich)
    # - Forward special connections as-is upstream (kanidm)
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

          ssl_preread on;
          proxy_pass $upstream;
          proxy_protocol on;
        }

        server {
          listen [::]:443;

          ssl_preread on;
          proxy_pass $upstream;
          proxy_protocol on;
        }
      '';

    # All configuration below is specific to the HTTP module!
    # eg both stream and http module have an "upstreams" block, but the nixos options configuration abstracts mostly over the
    # configuration for http specifically which becomes confusing.

    commonHttpConfig = ''
      # WARN; stream[+proxy_protocol] is forwarding to http(s) listener.
      # The value for `$remote_addr` will always be pointing to 127.0.0.1 (localhost equivalent) under default configuration.
      #
      # $remota_addr is set from the proxy protocol globally. Uses overrides per server block to restore functionality.
      set_real_ip_from unix:/run/nginx/https-frontend.sock;
      real_ip_header proxy_protocol;
    '';

    upstreams = {
      photos-upstream.servers."${config.services.immich.host}:${toString config.services.immich.port}" =
        { };
    };

    defaultListen = [
      {
        addr = "unix:/run/nginx/https-frontend.sock";
        proxyProtocol = true;
        ssl = true;
      }
      {
        addr = "0.0.0.0";
        port = 80;
        ssl = false;
      }
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
