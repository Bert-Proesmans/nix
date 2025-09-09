{ lib, config, ... }:
{
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  security.acme = {
    defaults.reloadServices = [ config.systemd.services.haproxy.name ];
    certs."alpha.proesmans.eu".group = "haproxy";
  };

  services.haproxy =
    let
      upstream.idm = rec {
        inherit (config.services.kanidm.serverSettings) origin bindaddress;
        aliases = [ "idm.proesmans.eu" ];
        # WARN; Domain and Origin are separate values from the effective DNS hostname.
        # REF; https://kanidm.github.io/kanidm/master/choosing_a_domain_name.html#recommendations
        hostname =
          assert origin == "https://idm.proesmans.eu";
          "alpha.idm.proesmans.eu";
        server = bindaddress;
      };
      upstream.passwords = rec {
        inherit (config.services.vaultwarden.config) ROCKET_ADDRESS ROCKET_PORT DOMAIN;
        aliases = [ "passwords.proesmans.eu" ];
        hostname =
          assert DOMAIN == "https://alpha.passwords.proesmans.eu";
          "alpha.passwords.proesmans.eu";
        server = "${ROCKET_ADDRESS}:${toString ROCKET_PORT}";
      };
      upstream.pictures = rec {
        inherit (config.services.immich) host port;
        inherit (config.services.immich.settings.server) externalDomain;
        aliases = [ "pictures.proesmans.eu" ];
        hostname =
          assert externalDomain == "https://pictures.proesmans.eu";
          "alpha.pictures.proesmans.eu";
        server = "${host}:${toString port}";
      };
      upstream.wiki = rec {
        inherit (config.services.outline) publicUrl port;
        aliases = [ "wiki.proesmans.eu" ];
        # TODO; Reintroduce check after figuring out proper domain settings for outline
        hostname =
          #assert publicUrl == "https://wiki.proesmans.eu"; # DEBUG
          "alpha.wiki.proesmans.eu";
        server = "localhost:${toString port}";
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
        crt-store alpha
          crt-base '${config.security.acme.certs."alpha.proesmans.eu".directory}'
          key-base '${config.security.acme.certs."alpha.proesmans.eu".directory}'
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
          acl trusted_proxies src 100.127.116.49 # add others separated by space eg, 100.0.0.2
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
              [ upstream.idm.hostname ] ++ upstream.idm.aliases
            )
          } }
          
          # anything else → locally terminated
          server localterm unix@/run/haproxy/local-https.sock send-proxy-v2

        frontend https_terminator
          description accept TLS handshakes and mangle packets
          mode http
          # accept proxy v2 from the tcp mux and terminate tls here
          bind unix@/run/haproxy/local-https.sock accept-proxy ssl crt '@alpha/fullchain.pem' alpn h2,http/1.1 accept-proxy

          log global
          # DEBUG
          #log-format "''${HAPROXY_HTTP_LOG_FMT} <backend=%[var(txn.backend_name)]> debug=%[var(txn.debug)]"
          # DEBUG
          # NOTE; Each enabled capture uses a bit of memory per stream
          #http-request capture req.hdr(Host)        len 80

          #http-request set-var-fmt(txn.debug) "alpn=%[ssl_fc_alpn] host='%[capture.req.hdr(0)]'"

          # do alias redirects
          http-request redirect prefix https://${upstream.pictures.hostname} code 302 if { ${
            lib.concatMapStringsSep " || " (alias: "hdr(host) -i ${alias}") upstream.pictures.aliases
          } }
          http-request redirect prefix https://${upstream.passwords.hostname} code 302 if { ${
            lib.concatMapStringsSep " || " (alias: "hdr(host) -i ${alias}") upstream.passwords.aliases
          } }
          http-request redirect prefix https://${upstream.wiki.hostname} code 302 if { ${
            lib.concatMapStringsSep " || " (alias: "hdr(host) -i ${alias}") upstream.wiki.aliases
          } }

          # host routing, use "host_xx" for specific overrides
          #
          # WARN; Add assignment for BACKEND NAME when adding a new host!
          acl host_pictures  req.hdr(Host) -i ${upstream.pictures.hostname}
          acl host_passwords req.hdr(Host) -i ${upstream.passwords.hostname}
          acl host_wiki      req.hdr(Host) -i ${upstream.wiki.hostname}

          http-request set-header X-Forwarded-Proto https
          http-request set-header X-Forwarded-Host  %[req.hdr(Host)]
          http-request set-header X-Forwarded-Server %[hostname]
          
          # HSTS (63072000 seconds)
          http-response set-header Strict-Transport-Security max-age=63072000

           # allow/deny large uploads similar to nginx's client_max_body_size (nginx default was 10M)
          http-request set-var(txn.max_body) str("10m")

          http-request set-var(txn.backend_name) str(upstream_pictures_app) if host_pictures
          http-request set-var(txn.max_body) str("500m") if host_pictures

          http-request set-var(txn.backend_name) str(upstream_passwords_app) if host_passwords
          
          http-request set-var(txn.backend_name) str(upstream_wiki_app) if host_wiki

          # enforce payload size, units in bytes          
          http-request set-var(txn.max_body_bytes) var(txn.max_body_str),bytes
          http-request set-var(txn.body_size_diff) var(req.body_size),sub(txn.max_body_bytes)
          http-request set-var(txn.cl_size_diff)   req.hdr_val(content-length),sub(txn.max_body_bytes)
          http-request deny status 413 if { var(txn.body_size_diff) -m int gt 0 }
          http-request deny status 413 if { var(txn.cl_size_diff) -m int gt 0 }

           # reject if no backend set (optional hardening)
          http-request deny status 421 if !{ var(txn.backend_name) -m found }

          use_backend %[var(txn.backend_name)]

        backend upstream_pictures_app
          description forward to pictures app
          mode http
          # ERROR; forwardfor doesn't work in default section, reason unknown
          option forwardfor     # adds X-Forwarded-For with client ip (non-standardized btw)
          server app ${upstream.pictures.server} check

        backend upstream_passwords_app
          description forward to passwords app
          mode http
          # ERROR; forwardfor doesn't work in default section, reason unknown
          option forwardfor     # adds X-Forwarded-For with client ip (non-standardized btw)
          server app ${upstream.passwords.server} check

        backend upstream_wiki_app
          description forward to wiki app
          mode http
          # ERROR; forwardfor doesn't work in default section, reason unknown
          option forwardfor     # adds X-Forwarded-For with client ip (non-standardized btw)
          server app ${upstream.wiki.server} check

        backend passthrough_idm
          description raw tcp/tls passthrough for kanidm with proxy protocol
          mode tcp
          # client → haproxy(:443) → 127.204.0.1:8443 (send PROXY v2 as required by Kanidm)
          server idm ${upstream.idm.server} send-proxy-v2 check
      '';
    };

  systemd.services.haproxy = {
    requires = [ "acme-alpha.proesmans.eu.service" ];
    after = [ "acme-alpha.proesmans.eu.service" ];
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
