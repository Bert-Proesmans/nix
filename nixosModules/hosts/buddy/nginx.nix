# Provide external endpoint that reverse proxies local services
{ lib, pkgs, config, ... }: {
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  security.acme.certs."alpha.proesmans.eu" = {
    group = config.services.nginx.group;
    reloadServices = [ config.systemd.services.nginx.name ];
  };

  services.nginx = {
    enable = true;
    package = pkgs.nginxMainline;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;
    recommendedProxySettings = true;
    recommendedGzipSettings = true;
    recommendedBrotliSettings = true;

    # Uncomment after solving issue https://github.com/NixOS/nixpkgs/issues/370905
    # Custom listener setup for the http module because we're passing through tcp-protocol traffic to kanidm upstream
    # defaultListen = [
    #   { addr = "unix:/run/nginx/virtualhosts.sock"; port = null; ssl = true; }
    #   { addr = "0.0.0.0"; port = 80; ssl = false; }
    #   { addr = "[::0]"; port = 80; ssl = false; }
    # ];

    upstreams = {
      # WARN; Only http frontend upstreams, no stream upstreams!
      photos.servers."${config.services.immich.host}:${toString config.services.immich.port}" = { };
    };

    virtualHosts =
      let
        # Upstream has a bug where it doesn't properly process the services.nginx.defaultListen data.
        # REF; https://github.com/NixOS/nixpkgs/issues/370905
        defaultListen = {
          listen = [
            { addr = "unix:/run/nginx/virtualhosts.sock"; port = null; ssl = true; }
            { addr = "0.0.0.0"; port = 80; ssl = false; }
            { addr = "[::0]"; port = 80; ssl = false; }
          ];
        };
      in
      {
        "default" = {
          default = true;
          rejectSSL = true;
          locations."/".return = "404";
        } // defaultListen;

        "alpha.idm.proesmans.eu" = {
          # Redirect to https without configuring https
          locations."/".return = "301 https://$host$request_uri";
          listen = [
            { addr = "0.0.0.0"; port = 80; ssl = false; }
            { addr = "[::0]"; port = 80; ssl = false; }
          ];
        };

        "photos.alpha.proesmans.eu" = {
          # Use the generated wildcard certificate, see security.acme.certs.<name>
          useACMEHost = "alpha.proesmans.eu";
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://photos"; # See nginx.upstreams.<name>
            proxyWebsockets = true;
            extraConfig = ''
              # Required for larger uploads to be possible (defaults at 10M)
              client_max_body_size 500M;
            '';
          };
        } // defaultListen;
      };

    # Redirect the Idm traffic into kanidm for end-to-end encryption using the stream module
    streamConfig =
      let
        server_name-kanidm = lib.strings.removePrefix "https://" config.services.kanidm.serverSettings.origin;
        upstream-kanidm = config.services.kanidm.serverSettings.bindaddress;
      in
      ''
        map $ssl_preread_server_name $upstream {
          default unix:/run/nginx/virtualhosts.sock;
          ${server_name-kanidm} ${upstream-kanidm};
        }

        # Extra frontends that redirects to kanidm or the configured virtualhosts.
        # The virtualhosts (http) listener must be bound to another listen address, since stream and http listeners cannot
        # bind to the same endpoint.
        server {
          listen 0.0.0.0:443;
          proxy_pass $upstream;
          ssl_preread on;
        }
        server {
          listen [::0]:443;
          proxy_pass $upstream;
          ssl_preread on;
        }
      '';
  };
}
