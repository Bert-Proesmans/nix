{ lib, config, ... }:
{
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  security.acme = {
    defaults.reloadServices = [ config.systemd.services.haproxy.name ];
    certs."omega.proesmans.eu".group = "haproxy";
  };

  # Allow r/w access to varnish ingest
  users.groups.varnish-forwarders.members = [ "haproxy" ];

  services.haproxy =
    let
      upstream.buddy = {
        aliases = [
          "idm.proesmans.eu"
          "omega.idm.proesmans.eu"
          "pictures.proesmans.eu"
          "omega.pictures.proesmans.eu"
        ];
        # WARN; Expecting the upstream to ingest our proxy frames based on IP ACL rule
        server = "100.116.84.29:443"; # Tailscale forward
      };
      # upstream.idm = rec {
      #   aliases = [ ];
      #   hostname = ;
      #   server = "100.116.84.29:443"; # Tailscale forward
      # };
      upstream.pictures = {
        # NOTE; Upstream is local varnish webcache
        aliases = [ "pictures.proesmans.eu" ];
        hostname = "omega.pictures.proesmans.eu";
        server = null; # Tailscale forward
      };
      certs.omega = {
        cert = "fullchain.pem";
        key = "key.pem";
        # Wildcard + multi-domain
        directory = config.security.acme.certs."omega.proesmans.eu".directory;
      };
    in
    {
      enable = true;
      config = ''
        global
          # logging goes to journald via stdout/stderr under systemd; no daemon/pidfile
          # (stats socket is injected by your nixos module; do not redefine here)
          # generated 2025-08-15, Mozilla Guideline v5.7, HAProxy 3.2, OpenSSL 3.4.0, intermediate config
          # https://ssl-config.mozilla.org/#server=haproxy&version=3.2&config=intermediate&openssl=3.4.0&guideline=5.7
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
          mode http
          option httplog
          option dontlognull
          option forwardfor     # adds X-Forwarded-For with client ip
          timeout connect 60s
          timeout client  65s
          timeout server  65s
          timeout tunnel  1h    # long-lived websocket/tunnel support
          http-reuse safe

          # NOTE; haproxy does not recompress if upstream has applied compression. This all depends on the Accept-Encoding header inside the requets.
          # gzip (haproxy has no brotli). mirror the nginx mime set as closely as haproxy allows.
          compression algo gzip
          compression type text/html text/plain text/css text/javascript application/javascript application/x-javascript application/json application/ld+json application/wasm application/xml application/xhtml+xml application/rss+xml application/atom+xml text/xml text/markdown text/vtt text/cache-manifest text/calendar text/csv font/ttf font/otf image/svg+xml application/vnd.ms-fontobject

        defaults tcp
          mode tcp
          option tcplog
          timeout connect 60s
          timeout client  65s
          timeout server  65s
          timeout tunnel  1h  # long-lived websocket/tunnel support

        crt-store omega
          crt-base '${certs.omega.directory}'
          key-base '${certs.omega.directory}'
          load crt '${certs.omega.cert}' key '${certs.omega.key}'

        # --- :80 → https redirect (keeps host + uri) ---
        frontend http_redirect
          mode http
          bind :80 v4v6
          http-request redirect scheme https code 301 unless { ssl_fc }

        # --- tcp tls mux on :443 with sni routing ---
        # this mirrors nginx `stream { ... }` behavior.
        frontend tls_muxing
          mode tcp
          bind :443 v4v6
          # inspect clienthello to get SNI
          tcp-request inspect-delay 5s
          tcp-request content accept if { req_ssl_hello_type 1 }

          # route by SNI
          use_backend passthrough_buddy if { ${
            lib.concatMapStringsSep " || " (sni: "req.ssl_sni -i ${sni}") upstream.buddy.aliases
          } }
          
          default_backend local_tls_termination # anything else → local terminator

        # --- tcp backend that points to a local unix-socket ssl terminator ---
        # we keep tcp here and hop via PROXY v2 into the terminator.
        backend local_tls_termination
          mode tcp
          server localterm unix@/run/haproxy/local-https.sock send-proxy-v2

        # --- https terminator over a unix socket (http mode after decryption) ---
        # this is the equivalent of nginx "listen unix:... ssl proxy_protocol" http server.
        frontend https_terminator
          mode http
          # accept proxy v2 from the tcp mux and terminate tls here
          bind unix@/run/haproxy/local-https.sock accept-proxy ssl crt '@omega/${certs.omega.cert}' alpn h2,http/1.1 accept-proxy

          # do alias redirects
          http-request redirect prefix https://${upstream.pictures.hostname} code 302 if { hdr(host) -i pictures.proesmans.eu }

          # allow/deny large uploads similar to nginx's client_max_body_size (nginx default was 10M)
          http-request set-var(txn.max_body) str("10m")

          # host routing, use "host_xx" for specific overrides
          #
          # WARN; Add assignment for BACKEND NAME when adding a new host!
          acl host_pictures  req.hdr(Host) -i ${upstream.pictures.hostname}

          http-request set-var(txn.backend_name) str(upstream_varnish) if host_pictures
          http-request set-var(txn.max_body) str("500m") if host_pictures

          # reject if no backend set (optional hardening)
          http-request deny status 421 if !{ var(txn.backend_name) -m found }

          # enforce payload size, units in bytes          
          http-request set-var(txn.max_body_bytes) var(txn.max_body_str),bytes
          http-request set-var(txn.body_size_diff) var(req.body_size),sub(txn.max_body_bytes)
          http-request set-var(txn.cl_size_diff)   req.hdr_val(content-length),sub(txn.max_body_bytes)
          http-request deny status 413 if { var(txn.body_size_diff) -m int gt 0 }
          http-request deny status 413 if { var(txn.cl_size_diff) -m int gt 0 }

          http-request set-header X-Forwarded-Proto https
          http-request set-header X-Forwarded-Host  %[req.hdr(Host)]
          http-request set-header X-Forwarded-Server %[hostname]
          
          # websocket friendliness (haproxy already handles Connection hop-by-hop headers,
          # but we preserve Upgrade semantics explicitly)
          acl is_websocket req.hdr(Upgrade) -i websocket
          http-request set-header Connection "upgrade" if is_websocket
          
          # HSTS (63072000 seconds)
          http-response set-header Strict-Transport-Security max-age=63072000

          use_backend %[var(txn.backend_name)]

        # --- http backend to the varnish ---
        backend upstream_varnish
          mode http
          server varnish1 unix@/run/varnishd/frontend.sock check send-proxy

        # --- raw tcp/tls passthrough with proxy protocol v2 ---
        # haproxy can originate v2 directly.
        backend passthrough_buddy
          mode tcp
          # client → haproxy(:443) → buddy(100.116.84.29:443) (send PROXY v2)
          server buddy_tailscale ${upstream.buddy.server} send-proxy-v2 check
      '';
    };

  systemd.services.haproxy = {
    requires = [ "acme-omega.proesmans.eu.service" ];
    after = [ "acme-omega.proesmans.eu.service" ];
  };

  # Ensure no other modules enable nginx, only Haproxy is deployed!
  services.nginx.enable = false;

  security.dhparams = {
    enable = true;
    # NOTE; Suggested by Mozilla TLS config generator
    defaultBitSize = 2048;
    # Name of parameter set must match the systemd service name!
    params.haproxy = {
      # Defaults are used.
      # Use 'params.haproxy.path' to retrieve the parameters.
    };
  };
}
