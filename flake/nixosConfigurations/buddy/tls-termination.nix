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
            "alpha.idm.proesmans.eu";
          location = "127.0.0.1:8443";
        };
    in
    {
      enable = true;
      config = ''
        global
          log stdout format raw local0 info
          # DEBUG
          # log stdout format raw local0 notice
          # generated 2025-08-15, Mozilla Guideline v5.7, HAProxy 3.2, OpenSSL 3.4.0, intermediate config
          # https://ssl-config.mozilla.org/#server=haproxy&version=3.2&config=intermediate&openssl=3.4.0&guideline=5.7
          #
          ssl-default-bind-curves X25519:prime256v1:secp384r1
          ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305
          ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
          ssl-default-bind-options prefer-client-ciphers ssl-min-ver TLSv1.2 no-tls-tickets
          ssl-default-server-curves X25519:prime256v1:secp384r1
          ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305
          ssl-default-server-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
          ssl-default-server-options ssl-min-ver TLSv1.2 no-tls-tickets
          ssl-dh-param-file '${config.security.dhparams.params.haproxy.path}'
          
        defaults
          timeout connect 5s
          timeout client 65s
          timeout server 65s
          timeout tunnel 1h

        listen http_plain
          description Redirect clients to https
          mode http
          bind :80 v4v6

          log global
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
          acl trusted_proxies src ${
            lib.concatMapStringsSep " " lib.escapeShellArg downstream.proxies.addresses
          }
          tcp-request connection expect-proxy layer4 if trusted_proxies
          
          # inspect clienthello to get SNI
          tcp-request inspect-delay 5s
          tcp-request content accept if { req_ssl_hello_type 1 }

          # route by SNI
          use_backend passthrough_kanidm if { req.ssl_sni -i ${lib.escapeShellArg services.idm.hostname} idm.proesmans.eu }
          
          # Default backend
          server local-nginx unix@/run/nginx/virtualhosts.sock send-proxy-v2

        backend passthrough_kanidm
          description raw tcp/tls passthrough for kanidm with proxy protocol
          mode tcp

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
    # Name of parameter set must match the systemd service name!
    params.haproxy = {
      # Defaults are used.
      # Use 'params.haproxy.path' to retrieve the parameters.
    };
    params.nginx = { };
  };

  security.acme = {
    certs."alpha-services.proesmans.eu" = {
      group = config.users.groups.nginx.name;
      reloadServices = [ config.systemd.services.nginx.name ];
    };
  };

  systemd.services.nginx = {
    requires = [ "acme-alpha-services.proesmans.eu.service" ];
    after = [ "acme-alpha-services.proesmans.eu.service" ];

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
