{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (config.proesmans.facts) buddy freddy;
in
{
  networking.firewall.allowedTCPPorts = [
    # TODO; Restrict port binding for haproxy user only
    80
    443
  ];

  services.haproxy =
    let
      upstream.buddy = {
        # Client -> Haproxy -> Buddy passthrough
        aliases = [
          "alpha.idm.proesmans.eu"
          "alpha.pictures.proesmans.eu"
        ];
        # WARN; Expecting the upstream to ingest our proxy frames based on IP ACL rule
        # NOTE; Using the tailscale address to tunnel between nodes.
        location = "${buddy.host.tailscale.address}:${toString buddy.service.reverse-proxy.port}";
      };
      upstream.freddy = {
        # Client -> Haproxy -> Freddy passthrough
        aliases = [
          "omega.idm.proesmans.eu"
          "passwords.proesmans.eu"
          "omega.passwords.proesmans.eu"
          "wiki.proesmans.eu"
          "omega.wiki.proesmans.eu"
        ];
        # WARN; Expecting the upstream to ingest our proxy frames based on IP ACL rule
        # NOTE; Using the tailscale address to tunnel between nodes.
        location = "${freddy.host.tailscale.address}:${toString freddy.service.reverse-proxy.port}";
      };
      loadbalance.idm = {
        aliases = [ "idm.proesmans.eu" ];
      };
      service.cache = {
        aliases = [
          "pictures.proesmans.eu"
          "omega.pictures.proesmans.eu"
        ];
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
          # DEBUG
          # stats socket /run/haproxy/haproxy.sock mode 600 expose-fd listeners level admin
          
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
          #
          # Additional buffer tweaks for immich media streaming
          tune.bufsize 32k
          maxconn 100000
          
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

          log global
          option tcplog
          option dontlognull
          
          # inspect clienthello to get SNI
          tcp-request inspect-delay 5s
          # reject stream if no clienthello was provided!
          tcp-request content accept if { req.ssl_hello_type 1 } { req.ssl_sni -m found }
          tcp-request content reject

          # route by SNI
          use_backend loadbalance_idm if { req.ssl_sni -i ${
            lib.concatMapStringsSep " " lib.escapeShellArg loadbalance.idm.aliases
          } }
          use_backend passthrough_buddy if { req.ssl_sni -i ${
            lib.concatMapStringsSep " " lib.escapeShellArg upstream.buddy.aliases
          } }
          use_backend passthrough_freddy if { req.ssl_sni -i ${
            lib.concatMapStringsSep " " lib.escapeShellArg upstream.freddy.aliases
          } }
          use_backend redirect_tls_cache if { req.ssl_sni -i ${
            lib.concatMapStringsSep " " lib.escapeShellArg service.cache.aliases
          } }

          # Default backend
          server local-nginx unix@/run/nginx/virtualhosts.sock send-proxy-v2

        # WARN; DO NOT check TLS certificate because Haproxy cannot handle CHECK with PROXY with TLS. The below options DO NOT work!
        # The TCP proxy node is also not the right location for TLS verification, only the end nodes are proper.
        # Use the tailscale peer IP for mutual TLS verification if MITM is a concern.
        #
        # "ssl verify required"
        # "ca-file /etc/ssl/certs/ca-bundle.crt"
        # "check-sni ${builtins.head upstream.freddy.aliases}"

        backend loadbalance_idm
          description raw tcp/tls passthrough with proxy protocol, fallback over multiple hosts
          mode tcp

          balance first

          # TODO; Figure out how health checks should be performed!
          # Ideally over TLS into Kanidm status endpoint

          server freddy ${upstream.freddy.location} id 1 send-proxy-v2 check
          server buddy ${upstream.buddy.location} id 2 send-proxy-v2 check

        backend passthrough_buddy
          description raw tcp/tls passthrough for buddy with proxy protocol
          mode tcp

          server buddy ${upstream.buddy.location} send-proxy-v2 check

        backend passthrough_freddy
          description raw tcp/tls passthrough for tcp with proxy protocol
          mode tcp

          server freddy ${upstream.freddy.location} send-proxy-v2 check

        backend redirect_tls_cache
          description Hairpin from tls handler into http(s) handler
          mode tcp

          server haproxy unix@/run/haproxy/tls_cache.sock send-proxy-v2

        ## CACHING BACKEND ##

        crt-store cache-omega
          crt-base '${config.security.acme.certs."cache-omega-services.proesmans.eu".directory}'
          key-base '${config.security.acme.certs."cache-omega-services.proesmans.eu".directory}'
          # NOTE; Wildcard + multiple domains certificate
          load crt 'fullchain.pem' key 'key.pem'

        listen tls_cache
          description Terminate TLS before forwarding to Varnish
          bind unix@/run/haproxy/tls_cache.sock mode 600 ssl crt '@cache-omega/fullchain.pem' alpn h2,http/1.1 accept-proxy
          mode http
          
          log global
          option httplog
          option dontlognull

          option http-server-close
          # Larger timeout for upload/download
          timeout server 10m
          timeout client 10m

          # Let Varnish know about the original client request
          http-request set-header X-Forwarded-Proto %[ssl_fc,iif(https,http)]
          http-request set-header X-Forwarded-Host %[req.hdr(host)]
          http-request set-header X-Forwarded-Server %[hostname]

          # NOTE; I gave up matching headers, since that produced very strange results!
          acl is_pictures_host hdr_end(host) -i pictures.proesmans.eu
          acl is_pictures_ws_path path_beg -i /api/socket.io/
          
          http-request set-header Host omega.pictures.proesmans.eu if is_pictures_host
          # ERROR; Split backend from path varnish -> haproxy due to http version with connection multiplexer mismatches!
          use_backend direct_to_freddy if is_pictures_host is_pictures_ws_path

          # Default
          server local-varnish unix@/run/varnishd/frontend.sock send-proxy-v2


        backend direct_to_freddy
          description Separate backend to properly split websocket from cache traffic. Pushing both over the same backend causes h1 packets on h2 multiplexer and other way around.
          mode http

          option http-server-close
          # no log
          log global

          server freddy ${upstream.freddy.location} send-proxy-v2 alpn h2,http/1.1 sni req.hdr(host) ssl verify required ca-file /etc/ssl/certs/ca-bundle.crt check no-check-ssl


        listen forward_to_freddy
          description Varnish community edition cannot upstream-connect over TLS, so this stanza wraps non-TLS requests to freddy with TLS
          bind unix@/run/haproxy/forward_to_freddy.sock group ${config.users.groups.haproxy.name} mode 660 accept-proxy
          # bind :8080 v4v6 # DEBUG
          mode http

          # no log
          log global
          option httplog
          option dontlognull

          no option checkcache
          # Larger timeout for upload/download
          timeout server 10m
          timeout client 10m

          # Haproxy sets up its own TLS tunnel instead of forwarding the tunnel creation.
          #
          # NOTE; sni override is explicitly required if request headers, like host, were manipulated for upstream use! Before entering
          # this (backend) block the sni must be known!
          #
          # ERROR; sni argument is processed _before_ per-request set-headers are in effect!
          # DO NOT USE 'sni %[var(req.new_host)]' => Doesn't evaluate because variable doesn't exist when upstream connection
          # is created.
          # USE 'sni req.hdr(host)' => If the frontend has corrected to the right upstream hostname
          #
          # NOTE; Using http2 protocol with reused backend connections should(?) reduce tcp connection overhead lowering total latency through channel multiplexing.
          # Http3 (quic) improves this further (no head-of-line blocking) but requires haproxy enterprise.
          #
          # In HTTP proxy mode we _must_ verify the endpoint certificate!
          server freddy ${upstream.freddy.location} send-proxy-v2 alpn h2,http/1.1 sni req.hdr(host) ssl verify required ca-file /etc/ssl/certs/ca-bundle.crt check no-check-ssl
      '';
    };

  security.acme = {
    certs."cache-omega-services.proesmans.eu" = {
      group = config.users.groups.haproxy.name;
      reloadServices = [
        config.systemd.services.haproxy.name
      ];
    };
  };

  systemd.services.haproxy = {
    # NOTE; Only cache-omega because haproxy terminates for varnish only
    requires = [ "acme-cache-omega-services.proesmans.eu.service" ];
    after = [ "acme-cache-omega-services.proesmans.eu.service" ];
    serviceConfig = {
      RestartSec = "5s";
      SupplementaryGroups = [
        # Allow Haproxy access to /run/nginx/virtualhosts.sock
        config.users.groups.nginx.name
        # Allow Haproxy access to /run/varnishd/frontend.sock
        config.users.groups.varnish.name
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
      "default.omega.proesmans.eu" = {
        default = true;
        # WARN; Nginx only receives TLS requests and a default instance also needs correct TLS configuration.
        useACMEHost = "local-omega-services.proesmans.eu";
        onlySSL = true;
        # ERROR; Browsers reuse the same connection(s) (in HTTP/2 MODE) when servers present a certificate that is valid
        # for the typed domain. Haproxy, proxying based on TLS SNI, could send the wrong request to an earlier forwarded upstream.
        # WARN; In my setup I use multiple certificates, the problematic situation is using _the same_ wildcard certificate for
        # services hosted on two different systems (like STATUS <-> PICTURES).
        # Returning 421 "Misdirected Request" will trigger the browser to use another connection.
        # REF; https://serverfault.com/a/1015832
        # REF; https://bugzilla.mozilla.org/show_bug.cgi?id=1222136
        locations."/".return = "421 'Misdirected Request'";
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
    params.haproxy = { };
  };

  security.acme = {
    certs."local-omega-services.proesmans.eu" = {
      group = config.users.groups.nginx.name;
      reloadServices = [
        config.systemd.services.nginx.name
      ];
    };
  };

  systemd.services.nginx = {
    requires = [ "acme-local-omega-services.proesmans.eu.service" ];
    after = [ "acme-local-omega-services.proesmans.eu.service" ];

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

  environment.systemPackages = [
    # NOTE; Querying haproxy admin socket requires socat eg;
    # echo "show errors" | sudo -u haproxy socat stdio /run/haproxy/haproxy.sock
    pkgs.socat
  ];
}
