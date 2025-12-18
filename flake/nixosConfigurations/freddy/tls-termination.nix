{
  lib,
  pkgs,
  config,
  ...
}:
{
  networking.firewall.allowedTCPPorts = [
    # TODO; Restrict port binding for haproxy user only
    80
    443
  ];

  services.haproxy =
    let
      downstream.proxies.addresses = [
        # IP-Addresses of all hosts that proxy to us
        # NOTE; Using the tailscale address to tunnel between nodes.
        # Tailscale should link over oracle subnet.
        config.proesmans.facts."01-fart".host.tailscale.address
        config.proesmans.facts."02-fart".host.tailscale.address
      ];
      services.idm =
        assert config.services.kanidm.serverSettings.bindaddress == "127.0.0.1:8443";
        {
          # WARN; Domain and Origin are separate values from the effective DNS hostname.
          # REF; https://kanidm.github.io/kanidm/master/choosing_a_domain_name.html#recommendations
          hostname =
            assert config.services.kanidm.serverSettings.origin == "https://idm.proesmans.eu";
            "omega.idm.proesmans.eu";
          location = "127.0.0.1:8443";
        };
    in
    {
      enable = true;
      # NOTE; Example timeouts
      # timeout connect 5s # Maximum time for client to finish handshake
      # timeout client 65s # Maximum idle time of client
      # timeout server 65s # Maximum idle time of upstream server
      # timeout queue 5s # Maximum wait time in Haproxy queue until slot to upstream is free
      # timeout tunnel 1h # Websocket idle time
      # timeout http-request 10s #
      # timeout http-keep-alive 2s #
      # timeout client-fin 1s #
      # timeout server-fin 1s #
      config = ''
        global
          log stdout format raw local0 info
          # DEBUG
          # log stdout format raw local0 notice
          
        defaults
          timeout connect 5s
          timeout client 65s
          timeout server 65s
          timeout tunnel 1h

        listen http_plain
          description Redirect clients to https
          mode http
          bind :80 v4v6

          option httplog
          option dontlognull

          http-request redirect scheme https code 301 unless { ssl_fc }

         listen tls_muxing
          description Perform sni-tls routing, this mirrors nginx `stream { ... }` behavior but Haproxy has proxy-v2 support
          mode tcp
          bind :443 v4v6

          # No logging here because of duplicate logs introduced by nginx which has more request context
          no log

          # Conditionally accept proxy protocol from tunnel hosts
          acl trusted_proxies src ${lib.concatStringsSep " " downstream.proxies.addresses}
          tcp-request connection expect-proxy layer4 if trusted_proxies
          
          # inspect clienthello to get SNI
          tcp-request inspect-delay 5s
          tcp-request content accept if { req_ssl_hello_type 1 }

          # route by SNI
          use_backend passthrough_kanidm if { req.ssl_sni -i "${services.idm.hostname}" "idm.proesmans.eu" }
          
          # Default backend
          server local-nginx unix@/run/nginx/virtualhosts.sock send-proxy-v2

        backend passthrough_kanidm
          description raw tcp/tls passthrough for kanidm with proxy protocol
          mode tcp
          
          log global          
          server idm ${services.idm.location} send-proxy-v2
      '';
    };

  systemd.services.haproxy = {
    serviceConfig = {
      RestartSec = "5s";
      SupplementaryGroups = [
        # Allow Haproxy access to /run/nginx/virtualhosts.sock
        config.users.groups.nginx.name
      ];
    };
  };

  services.nginx = {
    enable = true;
    package = pkgs.nginxMainline;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;
    recommendedProxySettings = true;
    recommendedGzipSettings = true;
    recommendedBrotliSettings = true;
    sslDhparam = config.security.dhparams.params.nginx.path;
    appendHttpConfig = ''
      # Enable access logging for crowdsec
      access_log syslog:server=unix:/dev/log;

      # trust proxy protocol and correctly represent client IP
      set_real_ip_from unix:;
      real_ip_header proxy_protocol;
    '';

    defaultListen = [
      {
        addr = "unix:/run/nginx/virtualhosts.sock";
        port = null;
        ssl = true;
        proxyProtocol = true;
      }
    ];

    virtualHosts = {
      "default" = {
        default = true;
        locations."/".return = "404";
      };
    };
  };

  security.dhparams = {
    enable = true;
    # NOTE; Suggested by Mozilla TLS config generator
    defaultBitSize = 2048;
    params.nginx = {
      # Defaults are used.
      # Use 'params.nginx.path' to retrieve the parameters.
    };
  };

  security.acme = {
    certs."omega-services.proesmans.eu" = {
      group = config.users.groups.nginx.name;
      reloadServices = [ config.systemd.services.nginx.name ];
    };

    certs."omega.passwords.proesmans.eu" = {
      group = config.users.groups.nginx.name;
      reloadServices = [ config.systemd.services.nginx.name ];
    };
  };

  systemd.services.nginx = {
    requires = [
      "acme-omega-services.proesmans.eu.service"
      "acme-omega.passwords.proesmans.eu.service"
    ];
    after = [
      "acme-omega-services.proesmans.eu.service"
      "acme-omega.passwords.proesmans.eu.service"
    ];

    serviceConfig = {
      # Restrict nginx from doing anything outside of muxing between unix socket and upstream services
      RestrictAddressFamilies = lib.mkForce [
        "AF_UNIX"
        "AF_INET"
      ];
      IPAddressDeny = "any";
      IPAddressAllow = "127.0.0.0/8";
    };
  };
}
