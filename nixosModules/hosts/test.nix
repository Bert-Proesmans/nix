{ lib, pkgs, config, ... }:
{
  networking.domain = "alpha.proesmans.eu";

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];

  environment.systemPackages = [
    pkgs.curl
    pkgs.socat
    pkgs.tcpdump
    pkgs.python3
    pkgs.nmap # ncat
    pkgs.proesmans.unsock
    pkgs.netcat-openbsd
    pkgs.proesmans.vsock-test
  ];

  security.acme = {
    # Self-signed certs
    acceptTerms = true;
    defaults = {
      email = "bproesmans@hotmail.com";
    };
  };

  systemd.services."acme-photos.alpha.proesmans.eu".serviceConfig.ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";

  # Override this service for fun and debug profit
  systemd.services."test".serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";

  services.nginx = {
    enable = true;
    package = pkgs.unsock.wrap pkgs.nginxStable;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;
    recommendedProxySettings = true; # DEBUG
    recommendedGzipSettings = true;
    # Triggers recompilation
    # Additional setting for server are automatically included
    recommendedBrotliSettings = true;

    # DEBUG; Log to stderr from debug upwards
    logError = "stderr debug";

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
            # { addr = "0.0.0.0"; port = 443; ssl = true; } # DEBUG
            # NOTE; Connections for each VHOST are accepted at port 80, where a redirect is
            # served into TLS. TLS connections are handled by the stream config (first).
            { addr = "0.0.0.0"; port = 80; ssl = false; }
          ];

          forceSSL = true;
        };
      in
      {
        "photos.alpha.proesmans.eu" = default-vhost-config // {
          enableACME = true; # DEBUG; self-signed cert
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
      #enable = false; # DEBUG
      proxies = [
        {
          to.socket.path = "/run/nginx-unsock/sso-upstream.vsock";
          to.vsock.cid = 2; # To hypervisor
          to.vsock.port = 10001;
        }
        {
          to.socket.path = "/run/nginx-unsock/photos-upstream.vsock";
          to.vsock.cid = 90000; # To guest 2-test
          to.vsock.port = 10000;
        }
      ];
    };

    serviceConfig = {
      # ERROR; Must manually open up the usage of VSOCKs.
      RestrictAddressFamilies = [ "AF_VSOCK" ];
    };
  };

  system.stateVersion = "24.05";
}
