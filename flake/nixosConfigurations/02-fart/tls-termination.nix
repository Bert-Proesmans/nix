{ lib, config, ... }:
let
  inherit (config.proesmans.facts) buddy freddy;
in
{
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  security.acme = {
    defaults.reloadServices = [ config.systemd.services.haproxy.name ];
    certs."omega.proesmans.eu".group = config.services.haproxy.group;
  };

  # Allow r/w access to varnish frontend socket
  users.groups.varnish-frontend.members = [ config.services.haproxy.group ];

  services.haproxy =
    let
      services.omega.idm = {
        hostname = "omega.idm.proesmans.eu";
        aliases = [ "idm.proesmans.eu" ];
        inherit (freddy.host.oracle) address;
        inherit (freddy.service.kanidm) port;
      };
      services.alpha.idm = {
        hostname = "alpha.idm.proesmans.eu";
        aliases = [ "idm.proesmans.eu" ];
        inherit (buddy.host.tailscale) address;
        inherit (buddy.service.kanidm) port;
      };
      services.status = {
        hostname = "omega.status.proesmans.eu";
        aliases = [ "status.proesmans.eu" ];
        inherit (config.services.gatus.settings.web) address port;
      };
    in
    {
      enable = true;
      config = ''
        global
          # (stats socket is injected by your nixos module; do not redefine here)
          #

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

          # Logging 
          #
          # Put state changes, warnings, errors and more problematic messages on stdout
          log stdout    format raw    local0  notice
          # Push "traffic logs" into systemd journal through syslog stub
          log /dev/log  format local  local7  info info

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
          # NOTE; Multiple domains certificate
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
          
          # inspect clienthello to get SNI
          tcp-request inspect-delay 5s
          tcp-request content accept if { req_ssl_hello_type 1 }
          # DEBUG
          # NOTE; Each enabled capture uses a bit of memory per stream
          # tcp-request content capture req.ssl_sni len 100

          # route by SNI
          use_backend passthrough_idm if { ${
            lib.concatMapStringsSep " || " (sni: "req.ssl_sni -i ${sni}") (
              lib.unique (
                [
                  services.omega.idm.hostname
                  services.alpha.idm.hostname
                ]
                ++ services.omega.idm.aliases
                ++ services.alpha.idm.aliases
              )
            )
          } }
          
          # anything else → locally terminated
          server localterm unix@/run/haproxy/local-https.sock send-proxy-v2

        backend passthrough_idm
          description raw tcp passthrough with proxy protocol v2
          mode tcp
          
          # client → haproxy(:443) → kanidm(:443) (send PROXY v2 as required by Kanidm)

          # Always prefer omega instance(s) of kanidm, otherwise alpha master node.
          balance first

          # WARN; Explicitly enable ssl verification during check to prevent logspam (logged) at kanidm
          option tcp-check
          tcp-check send QUIT\r\n
          server omega_idm ${services.omega.idm.address}:${toString services.omega.idm.port} id 1 send-proxy-v2 check # check-sni ${services.omega.idm.hostname} check-ssl verify none
          server alpha_idm ${services.alpha.idm.address}:${toString services.alpha.idm.port} id 2 send-proxy-v2 check # check-sni ${services.alpha.idm.hostname} check-ssl verify none

        frontend https_terminator
          description accept TLS handshakes and mangle packets
          mode http
          bind unix@/run/haproxy/local-https.sock ssl crt '@omega/fullchain.pem' alpn h2,http/1.1 accept-proxy

          log global
          # DEBUG
          #log-format "''${HAPROXY_HTTP_LOG_FMT} <backend=%[var(txn.backend_name)]> debug=%[var(txn.debug)]"
          # DEBUG
          # NOTE; Each enabled capture uses a bit of memory per stream
          #http-request capture req.hdr(Host)        len 80
          #http-request capture req.hdr(Upgrade)     len 20
          #http-request capture req.hdr(Connection)  len 20
          #http-request capture req.fhdr(:method)    len 20
          #http-request capture req.fhdr(:protocol)  len 20

          #http-request set-var-fmt(txn.debug) "alpn=%[ssl_fc_alpn] ws=%[var(txn.is_ws)] h1_ws=%[var(txn.is_ws_h1)] h2_ws=%[var(txn.is_ws_h2)] host='%[capture.req.hdr(0)]' up='%[capture.req.hdr(1)]' conn='%[capture.req.hdr(2)]' m='%[capture.req.hdr(3)]' protohdr='%[capture.req.hdr(4)]'"

          # do alias redirects
          http-request redirect prefix https://${services.status.hostname} code 302 if { ${
            lib.concatMapStringsSep " || " (alias: "hdr(host) -i ${alias}") services.status.aliases
          } }

          # host routing, use "host_xx" for specific overrides
          #
          # HELP; Add flags for new proxied hosts below!
          acl host_status req.hdr(Host) -i ${services.status.hostname}

          http-request set-header X-Forwarded-Proto https
          http-request set-header X-Forwarded-Host  %[req.hdr(Host)]
          http-request set-header X-Forwarded-Server %[hostname]
          
          # HSTS (63072000 seconds)
          http-response set-header Strict-Transport-Security max-age=63072000

          # allow/deny large uploads similar to nginx's client_max_body_size (nginx default was 10M)
          http-request set-var(txn.max_body) str("10m")

          http-request set-var(txn.backend_name) str(upstream_status_app) if host_status

          # reject if no backend set (optional hardening)
          http-request deny status 421 if !{ var(txn.backend_name) -m found }

          use_backend %[var(txn.backend_name)]

        backend upstream_status_app
          description forward to status app
          mode http
          # ERROR; forwardfor doesn't work in default section, reason unknown
          option forwardfor     # adds X-Forwarded-For with client ip (non-standardized btw)
          server app ${services.status.address}:${toString services.status.port} check
      '';
    };

  systemd.services.haproxy = {
    requires = [ "acme-omega.proesmans.eu.service" ];
    after = [ "acme-omega.proesmans.eu.service" ];
  };

  # Add members to group haproxy-frontend for r/w access to /run/haproxy-sockets/frontend.sock
  users.groups.haproxy-frontend.members = [ config.services.haproxy.group ];
  systemd.tmpfiles.settings."50-haproxy-sockets" = {
    "/run/haproxy-sockets".d = {
      user = config.services.haproxy.user;
      group = config.users.groups.haproxy-frontend.name;
      mode = "0755";
    };
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
