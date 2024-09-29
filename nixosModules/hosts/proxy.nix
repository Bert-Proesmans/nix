{ lib, pkgs, config, flake, ... }: {
  networking.domain = "alpha.proesmans.eu";

  # DEBUG
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];
  # DEBUG

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # WARN; Customisations to make NGINX compatible with UNSOCK
  proesmans.fixes.unsock-nginx.enable = true;

  services.nginx = {
    enable = true;
    package = pkgs.unsock.wrap pkgs.nginxStable;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;
    recommendedProxySettings = true;
    recommendedGzipSettings = true;
    # Triggers recompilation
    # Additional setting for server are automatically included
    recommendedBrotliSettings = true;

    # DEBUG; Log to stderr from debug upwards
    # logError = "stderr debug";

    # Snoop all connections and;
    #
    # - Either terminate on host
    # - Forward special connections as-is upstream
    streamConfig = ''
      upstream https-frontend {
          server unix:/run/nginx/https-frontend.sock;
      }

      upstream sso-upstream {
          server unix:/run/nginx-unsock/sso-upstream.vsock;
      }

      map $ssl_preread_server_name $upstream {
        default https-frontend;
        alpha.idm.proesmans.eu sso-upstream;
      }

      server {
        listen 0.0.0.0:443;

        proxy_pass $upstream;
        ssl_preread on;
      }
    '';

    virtualHosts =
      let
        default-vhost-config = {
          # WARN; Need a special listen setup because the default listen fallback adds ports
          # to the unix sockets, due to incomplete filtering.
          listen = [
            { addr = "unix:/run/nginx/https-frontend.sock"; ssl = true; }
            # NOTE; Attribute set below is used for the non-ssl redirect stanza
            { addr = "0.0.0.0"; port = 80; ssl = false; }
          ];

          forceSSL = true;
          sslCertificate = "/run/credentials/nginx.service/FULLCHAIN_PEM";
          sslCertificateKey = "/run/credentials/nginx.service/KEY_PEM";
        };
      in
      {
        "photos.alpha.proesmans.eu" = default-vhost-config // {
          locations."/".proxyPass = "http://photos-upstream";
        };
      };

    upstreams = {
      photos-upstream.servers."unix:/run/nginx-unsock/photos-upstream.vsock" = { };
    };
  };

  systemd.services.nginx = {
    unsock = {
      enable = true;
      proxies = [
        {
          to.socket.path = "/run/nginx-unsock/sso-upstream.vsock";
          to.vsock.cid = 300; # To SSO
          to.vsock.port = 8443;
        }
        {
          to.socket.path = "/run/nginx-unsock/photos-upstream.vsock";
          to.vsock.cid = 42; # To Photos
          to.vsock.port = 8080;
        }
      ];
    };

    serviceConfig = {
      # ERROR; Must manually open up the usage of VSOCKs.
      RestrictAddressFamilies = [ "AF_VSOCK" ];

      LoadCredential = [
        # WARN; Certificate files must be loaded into the unit credential store because
        # the original files require root access. This unit executes with user kanidm permissions.
        "FULLCHAIN_PEM:${config.microvm.suitcase.secrets."certificates".path}/fullchain.pem"
        "KEY_PEM:${config.microvm.suitcase.secrets."certificates".path}/key.pem"
      ];
    };
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
