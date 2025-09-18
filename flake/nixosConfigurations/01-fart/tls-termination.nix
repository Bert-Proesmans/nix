{ lib, config, ... }:
let
  buddy-tailscale-ip = lib.pipe config.proesmans.facts.buddy.services [
    # Want the service endpoint over tailscale
    (lib.filterAttrs (_ip: v: builtins.elem "tailscale" v.tags))
    (lib.mapAttrsToList (ip: _: ip))
    (lib.flip builtins.elemAt 0)
  ];
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
      upstream.buddy = {
        # Always forward these domains to buddy
        aliases = [ ];
        # WARN; Expecting the upstream to ingest our proxy frames based on IP ACL rule
        server = "${buddy-tailscale-ip}:443"; # Tailscale forward
      };
      upstream.pictures = {
        # NOTE; Upstream is local varnish webcache
        aliases = [ "pictures.proesmans.eu" ];
        hostname = "omega.pictures.proesmans.eu";
        server = null; # Varnish forward
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

          # Workarounds
          #
          # ERROR; Firefox attempts to upgrade to websockets over HTTP1.1 protocol with a bogus HTTP2 version tag.
          # The robust thing to do is to return an error.. but that doesn't help the users with a shitty client!
          #
          # NOTE; What exactly happens is ALPN negotiates H2 between browser and haproxy. This triggers H2 specific flows in 
          # both programs with haproxy strictly applying standards and firefox farting all over.
          h2-workaround-bogus-websocket-clients
          # TODO; Tweak(?) tune.h2.be.initial-window-size / tune.h2.fe.initial-window-size to improve window size ?
          # This will make bandwidth usage unfair for a possible better latency experience for the user. 

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
          
          # inspect clienthello to get SNI
          tcp-request inspect-delay 5s
          tcp-request content accept if { req_ssl_hello_type 1 }
          # DEBUG
          # NOTE; Each enabled capture uses a bit of memory per stream
          # tcp-request content capture req.ssl_sni len 100

          # route by SNI
          use_backend passthrough_buddy if { ${
            lib.concatMapStringsSep " || " (sni: "req.ssl_sni -i ${sni}") upstream.buddy.aliases
          } }
          
          # anything else → locally terminated
          server localterm unix@/run/haproxy/local-https.sock send-proxy-v2

        backend passthrough_buddy
          description raw tcp passthrough with proxy protocol v2
          mode tcp
          # client → haproxy(:443) → buddy(:443) -> alpha_kanidm(:8443) (send PROXY v2)
          server buddy_tailscale ${upstream.buddy.server} send-proxy-v2 check

        frontend https_terminator
          description accept TLS handshakes and mangle packets
          mode http
          bind unix@/run/haproxy/local-https.sock accept-proxy ssl crt '@omega/fullchain.pem' alpn h2,http/1.1 accept-proxy

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
          http-request redirect prefix https://${upstream.pictures.hostname} code 302 if { ${
            lib.concatMapStringsSep " || " (alias: "hdr(host) -i ${alias}") upstream.pictures.aliases
          } }

          # http/1.1 websocket detection
          #
          # NOTE; HTTP_2.0 is a built-in ACL
          #
          acl is_websocket req.hdr(Upgrade) -i websocket
          acl is_upgrade   req.hdr(Connection) -i upgrade
          http-request set-var(txn.is_ws_h1) bool(true) if is_websocket is_upgrade !HTTP_2.0

          # http/2 websocket detection
          #
          # SEEALSO; global > h2-workaround-bogus-websocket-clients
          #
          acl h2_ws_connect  req.hdr(:method)  -i CONNECT
          acl h2_ws_protocol req.hdr(:protocol) -i websocket
          http-request set-var(txn.is_ws_h2) bool(true) if h2_ws_connect h2_ws_protocol HTTP_2.0

          http-request set-var(txn.is_ws) bool(true) if { var(txn.is_ws_h1) -m bool } or { var(txn.is_ws_h2) -m bool }

          # log explicitly when acl matches
          http-request set-var(txn.ws_detected) str(http1.1) if is_websocket is_upgrade
          http-request set-var(txn.ws_detected) str(http2)   if h2_ws_connect h2_ws_protocol

          # host routing, use "host_xx" for specific overrides
          #
          # HELP; Add flags for new proxied hosts below!
          acl host_pictures req.hdr(Host) -i ${upstream.pictures.hostname}

          http-request set-header X-Forwarded-Proto https
          http-request set-header X-Forwarded-Host  %[req.hdr(Host)]
          http-request set-header X-Forwarded-Server %[hostname]
          
          # HSTS (63072000 seconds)
          http-response set-header Strict-Transport-Security max-age=63072000

          # allow/deny large uploads similar to nginx's client_max_body_size (nginx default was 10M)
          http-request set-var(txn.max_body) str("10m")

          http-request set-var(txn.backend_name) str(to_varnish) if host_pictures !is_websocket !is_upgrade
          http-request set-var(txn.max_body) str("500m") if host_pictures

          # enforce payload size, units in bytes          
          http-request set-var(txn.max_body_bytes) var(txn.max_body_str),bytes
          http-request set-var(txn.body_size_diff) var(req.body_size),sub(txn.max_body_bytes)
          http-request set-var(txn.cl_size_diff) req.hdr_val(content-length),sub(txn.max_body_bytes)
          http-request deny status 413 if { var(txn.body_size_diff) -m int gt 0 }
          http-request deny status 413 if { var(txn.cl_size_diff) -m int gt 0 }          

          # short-circuit websockets
          http-request set-var(txn.backend_name) str(tls_to_buddy) if host_pictures { var(txn.is_ws) -m bool }
          
          # transform omega.<domain> -> alpha.<domain> if websocket forwarding
          #
          acl host_is_omega hdr_beg(host) -i omega.
          # NOTE; Documentation is unclear if this does the logical thing abstracted over both http1.1 and http2..
          # (Maybe need to use set-uri)
          http-request set-header Host %[req.hdr(Host),regsub(^omega\.,alpha.,)] if { var(txn.is_ws) -m bool } host_is_omega

          # reject if no backend set (optional hardening)
          http-request deny status 421 if !{ var(txn.backend_name) -m found }

          use_backend %[var(txn.backend_name)]

        backend to_varnish
          description http backend to the varnish web cache
          mode http

          # transform omega.<domain> -> alpha.<domain>
          #
          # NOTE; HTTP header 'host' is updated before delivering to varnish to have consistency between request and response.
          #
          acl host_is_omega hdr_beg(host) -i omega.
          # NOTE; Documentation is unclear if this does the logical thing abstracted over both http1.1 and http2..
          http-request set-header Host %[req.hdr(Host),regsub(^omega\.,alpha.,)]

          server varnish unix@/run/varnish-sockets/frontend.sock check send-proxy-v2

        listen tls_to_buddy
          description varnish community edition cannot connect upstream over TLS, so this is a hairpin (with proxy-v2)
          mode http
          bind unix@/run/haproxy-sockets/frontend.sock accept-proxy group haproxy-frontend mode 660
          # bind 127.0.0.1:6666 # DEBUG

          # client → haproxy(:443) → varnish(unix-socket) → haproxy(unix-socket) → buddy(100.116.84.29:443) (send PROXY v2)
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
          server default ${upstream.buddy.server} send-proxy-v2 check alpn h2,http/1.1 ssl verify required ca-file /etc/ssl/certs/ca-bundle.crt sni req.hdr(host)
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
