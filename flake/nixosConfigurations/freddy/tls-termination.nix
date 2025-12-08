{
  lib,
  pkgs,
  config,
  ...
}:
{
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  users.groups.nginx-frontend.members = [
    "nginx"
    "haproxy"
  ];

  security.acme = {
    certs."omega.proesmans.eu".group = config.users.groups.nginx-frontend.name;
    certs."omega.proesmans.eu".reloadServices = [
      config.systemd.services.haproxy.name
      config.systemd.services.nginx.name
    ];
  };

  # NOTE; Haproxy only does TLS muxing, it's not serving sites. Nginx is serving sites.
  services.haproxy =
    let
      downstream.proxies.addresses = [
        # IP-Addresses of all hosts that proxy to us
        config.proesmans.facts."01-fart".host.oracle.address
        config.proesmans.facts."02-fart".host.oracle.address
      ];

      upstream.local-nginx = rec {
        aliases = [
          "wiki.proesmans.eu"
          "omega.wiki.proesmans.eu"
        ];
        hostname = "omega.proesmans.eu";
        server = "/run/nginx-sockets/virtualhosts.sock";
      };

      services.idm =
        assert config.services.kanidm.serverSettings.bindaddress == "127.0.0.1:8443";
        {
          # WARN; Domain and Origin are separate values from the effective DNS hostname.
          # REF; https://kanidm.github.io/kanidm/master/choosing_a_domain_name.html#recommendations
          hostname =
            assert config.services.kanidm.serverSettings.origin == "https://idm.proesmans.eu";
            "omega.idm.proesmans.eu";
          aliases = [ "idm.proesmans.eu" ];
          address = "127.0.0.1";
          port = 8443;
        };
      services.passwords =
        assert config.services.vaultwarden.config.ROCKET_ADDRESS == "127.0.0.1";
        {
          hostname =
            assert config.services.vaultwarden.config.DOMAIN == "https://passwords.proesmans.eu";
            "omega.passwords.proesmans.eu";
          aliases = [ "passwords.proesmans.eu" ];
          address = config.services.vaultwarden.config.ROCKET_ADDRESS;
          port = config.services.vaultwarden.config.ROCKET_PORT;
        };
    in
    {
      enable = true;
      config = ''
        global
          # (stats socket is injected by your nixos module; do not redefine here)
          #

        defaults
          mode http
          option httplog
          option dontlognull
          option forwarded      # adds forwarded with forwarding information (Preferred to forwardfor, IETF RFC7239)
          timeout connect 60s
          timeout client  65s
          timeout server  65s
          timeout tunnel  1h    # long-lived websocket/tunnel support

          # Allow server-side websocket connection termination
          option http-server-close

          # Side-effect free use and reuse of upstream connections
          http-reuse safe

          # NOTE; haproxy does not recompress if upstream has applied compression. This all depends on the Accept-Encoding header inside the requets.
          # gzip (haproxy has no brotli). mirror the nginx mime set as closely as haproxy allows.
          compression algo gzip deflate
          compression type text/html text/plain text/css text/javascript application/javascript application/x-javascript application/json application/ld+json application/wasm application/xml application/xhtml+xml application/rss+xml application/atom+xml text/xml text/markdown text/vtt text/cache-manifest text/calendar text/csv font/ttf font/otf image/svg+xml application/vnd.ms-fontobject

        defaults tcp
          mode tcp
          option tcplog
          timeout connect 60s
          timeout client  65s
          timeout server  65s
          timeout tunnel  1h  # long-lived websocket/tunnel support

        # Manual certificate enlisting because the filenames do not match the expected syntax
        crt-store omega
          crt-base '${config.security.acme.certs."omega.proesmans.eu".directory}'
          key-base '${config.security.acme.certs."omega.proesmans.eu".directory}'
          # NOTE; Wildcard + multiple domains certificate
          load crt 'fullchain.pem' key 'key.pem'

        listen http_plain
          description replies with a redirect to https
          mode http
          bind :80 v4v6
          http-request redirect scheme https code 301 unless { ssl_fc }

        listen tls_muxing
          description tcp tls mux with sni routing, this mirrors nginx `stream { ... }` behavior
          mode tcp
          bind :443 v4v6

          # Conditionally accept proxy protocol from tunnel hosts
          acl trusted_proxies src ${lib.concatStringsSep " " downstream.proxies.addresses}
          tcp-request connection expect-proxy layer4 if trusted_proxies
          
          # inspect clienthello to get SNI
          tcp-request inspect-delay 5s
          tcp-request content accept if { req_ssl_hello_type 1 }
          # DEBUG
          # NOTE; Each enabled capture uses a bit of memory per stream
          # tcp-request content capture req.ssl_sni len 100

          # route by SNI
          use_backend passthrough_idm if { ${
            lib.concatMapStringsSep " || " (sni: "req.ssl_sni -i ${sni}") (
              [ services.idm.hostname ] ++ services.idm.aliases
            )
          } }

          use_backend passthrough_local_nginx if { ${
            lib.concatMapStringsSep " || " (sni: "req.ssl_sni -i ${sni}") (
              [ upstream.local-nginx.hostname ] ++ upstream.local-nginx.aliases
            )
          } }
          
          # anything else → locally terminated
          server localterm unix@/run/haproxy/local-https.sock send-proxy-v2

        backend passthrough_idm
          description raw tcp/tls passthrough for kanidm with proxy protocol
          mode tcp
          # client → haproxy(:443) → local instance (send PROXY v2 as required by Kanidm)
          # WARN; Explicitly enable ssl verification during check to prevent logspam (logged) at kanidm
          option tcp-check
          tcp-check send QUIT\r\n
          server idm ${services.idm.address}:${toString services.idm.port} send-proxy-v2 check check-sni ${services.idm.hostname} check-ssl verify none

        backend passthrough_local_nginx
          description raw tcp passthrough with proxy protocol v1 (nginx community doesn\'t support v2)
          mode tcp
          server local_nginx unix@${upstream.local-nginx.server} send-proxy check

        frontend https_terminator
          description accept TLS handshakes and mangle packets
          mode http
          # accept proxy v2 from the tcp mux and terminate tls here
          bind unix@/run/haproxy/local-https.sock accept-proxy ssl crt '@omega/fullchain.pem' alpn h2,http/1.1 accept-proxy

          # do alias redirects
          http-request redirect prefix https://${services.passwords.hostname} code 302 if { ${
            lib.concatMapStringsSep " || " (alias: "hdr(host) -i ${alias}") services.passwords.aliases
          } }

          # host routing, use "host_xx" for specific overrides
          #
          # WARN; Add assignment for BACKEND NAME when adding a new host!
          acl host_passwords req.hdr(Host) -i ${services.passwords.hostname}

          http-request set-header X-Forwarded-Proto https
          http-request set-header X-Forwarded-Host  %[req.hdr(Host)]
          http-request set-header X-Forwarded-Server %[hostname]
          
          # HSTS (63072000 seconds)
          http-response set-header Strict-Transport-Security max-age=63072000

            # allow/deny large uploads similar to nginx's client_max_body_size (nginx default was 10M)
          http-request set-var(txn.max_body) str("10m")


          http-request set-var(txn.backend_name) str(upstream_passwords_app) if host_passwords


          # enforce payload size, units in bytes          
          http-request set-var(txn.max_body_bytes) var(txn.max_body_str),bytes
          http-request set-var(txn.body_size_diff) var(req.body_size),sub(txn.max_body_bytes)
          http-request set-var(txn.cl_size_diff)   req.hdr_val(content-length),sub(txn.max_body_bytes)
          http-request deny status 413 if { var(txn.body_size_diff) -m int gt 0 }
          http-request deny status 413 if { var(txn.cl_size_diff) -m int gt 0 }

            # reject if no backend set (optional hardening)
          http-request deny status 421 if !{ var(txn.backend_name) -m found }

          use_backend %[var(txn.backend_name)]

        backend upstream_passwords_app
          description forward to passwords app
          mode http
          # ERROR; forwardfor doesn't work in default section, reason unknown
          option forwardfor     # adds X-Forwarded-For with client ip (non-standardized btw)
          server app ${services.passwords.address}:${toString services.passwords.port} check
      '';
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
        addr = "unix:/run/nginx-sockets/virtualhosts.sock";
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
    params.nginx = {
      # Defaults are used.
      # Use 'params.nginx.path' to retrieve the parameters.
    };
  };

  systemd.tmpfiles.settings."50-nginx-sockets" = {
    "/run/nginx-sockets".d = {
      user = "nginx";
      group = config.users.groups.nginx-frontend.name;
      mode = "0755";
    };
  };
}
