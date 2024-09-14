{ lib, pkgs, config, flake, ... }: {
  networking.domain = "alpha.proesmans.eu";

  # DEBUG
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];
  # DEBUG

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  environment.systemPackages = [ pkgs.proesmans.vsock-test ];

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
          server 127.175.0.0:8000;
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
          # DEBUG; Nginx is doing something weird by stalling to reply with upstream data until
          # proxy read timeout. All systems and tunnels work as expected, except this weird
          # nginx behaviour .. 
          #
          # Nginx is sending connection: Close to upstream, even tough that's not what is
          # configured.
          # Upstream replies with connection: close and a body, even closes the connection
          # yet nginx hangs.
          # extraConfig = ''
          #   proxy_set_header Connection "close";
          #   proxy_buffering off;
          # '';
        };
      in
      {
        "photos.alpha.proesmans.eu" = default-vhost-config // {
          locations."/".proxyPass = "http://127.175.0.0:8010";
        };
      };
  };

  systemd.services.nginx = {
    unsock = {
      enable = true;
      ip-scope = "127.175.0.0/32";
      proxies =
        let
          my-hypervisor = config.proesmans.facts.meta.parent;
          cid-shared-hosts = lib.pipe flake.outputs.host-facts [
            (lib.filterAttrs (_: v: v.meta.parent == my-hypervisor))
            (lib.mapAttrs' (_: v: lib.nameValuePair v.host-name v.meta.vsock-id))
          ];
        in
        [
          {
            match.port = 8000; # sso-upstream
            to.vsock.cid = 2; # Directly to hypervisor, see proxy-vm.nix
            to.vsock.port = 10001;
          }
          {
            # Go through proxy setup by the hypervisor
            match.port = 8010; # photos-upstream
            to.vsock.cid = 2; # Directly to hypervisor, see proxy-vm.nix
            to.vsock.port = 10000;
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
