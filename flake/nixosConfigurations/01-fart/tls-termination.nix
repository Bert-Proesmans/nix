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
      upstream.buddy = {
        # Always forward these domains to buddy
        aliases = [
          "alpha.idm.proesmans.eu"
        ];
        # WARN; Expecting the upstream to ingest our proxy frames based on IP ACL rule
        location = "${buddy.host.tailscale.address}:${toString buddy.service.reverse-proxy.port}";
      };
      upstream.freddy = {
        # Always forward these domains to freddy
        aliases = [
          "omega.idm.proesmans.eu"
          "idm.proesmans.eu"
          "omega.passwords.proesmans.eu"
          "passwords.proesmans.eu"
          "wiki.proesmans.eu"
          "omega.wiki.proesmans.eu"
        ];
        # WARN; Expecting the upstream to ingest our proxy frames based on IP ACL rule
        location = "${freddy.host.oracle.address}:${toString freddy.service.reverse-proxy.port}";
      };
      service.pictures = {
        hostname = "omega.pictures.proesmans.eu";
        aliases = [ "pictures.proesmans.eu" ];
        # NOTE; Upstream is local varnish webcache
        location = "unix@/run/varnish-sockets/frontend.sock";
      };
      service.status =
        assert config.services.gatus.settings.web.address == "127.0.0.1";
        {
          hostname = "omega.status.proesmans.eu";
          aliases = [ "status.proesmans.eu" ];
          location = "127.0.0.1:${toString config.services.gatus.settings.web.port}";
        };
    in
    {
      enable = true;
      settings = {
        recommendedTlsSettings = true;

        global = {
          sslDhparam = config.security.dhparams.params.haproxy.path;
          extraConfig = ''
            # Workarounds
            #
            # ERROR; Firefox attempts to upgrade to websockets over HTTP1.1 protocol with a bogus HTTP2 version tag.
            # The robust thing to do is to return an error.. but that doesn't help the users with a shitty client!
            #
            # NOTE; What exactly happens is ALPN negotiates H2 between browser and haproxy. This triggers H2 specific flows in 
            # both programs with haproxy strictly applying standards and firefox farting all over.
            h2-workaround-bogus-websocket-clients

            # DEBUG
            log stdout format raw local0 notice
          '';
        };

        defaults."" = {
          # Anonymous defaults section.
          # Using anonymous defaults section is highly discouraged!
          timeout = {
            connect = "15s";
            client = "65s";
            server = "65s";
            tunnel = "1h";
          };

          option = [
            "dontlognull"
          ];

          extraConfig = ''
            log global
          '';
        };

        crt-stores.omega.extraConfig = ''
          crt-base '${config.security.acme.certs."omega.proesmans.eu".directory}'
          key-base '${config.security.acme.certs."omega.proesmans.eu".directory}'
          # NOTE; Wildcard + multiple domains certificate
          load crt 'fullchain.pem' key 'key.pem'
        '';

        frontend.http_plain = {
          mode = "http";
          bind = [ ":80 v4v6" ];
          option = [
            "httplog"
            "dontlognull"
          ];
          # This is a stub that redirects the client to https
          request = [ "redirect scheme https code 301 unless { ssl_fc }" ];
        };

        listen.tls_mux = {
          mode = "tcp";
          bind = [ ":443 v4v6" ];
          option = [ "tcplog" ];
          # No logging here because duplicate logs introduced by hairpin into https_terminator
          extraConfig = ''
            # no log
          '';

          request = [
            "inspect-delay 5s"
            "content accept if { req_ssl_hello_type 1 }"
          ];

          acl.buddy_request = lib.concatMapStringsSep " || " (fqdn: "req.ssl_sni -i ${fqdn}") (
            upstream.buddy.aliases
          );
          acl.freddy_request = lib.concatMapStringsSep " || " (fqdn: "req.ssl_sni -i ${fqdn}") (
            upstream.freddy.aliases
          );
          backend = [
            {
              name = "buddy_passthrough";
              condition = "buddy_request";
            }
            {
              name = "freddy_passthrough";
              condition = "freddy_request";
            }
          ];

          server.local = "unix@/run/haproxy/local-https.sock send-proxy-v2";
        };

        backend.freddy_passthrough = {
          mode = "tcp";
          server.freddy = {
            inherit (upstream.freddy) location;
            extraOptions = lib.concatStringsSep " " [
              # "send-proxy-v2"
              # "check"
              # "ssl verify required"
              # "ca-file /etc/ssl/certs/ca-bundle.crt"
              # "check-sni ${builtins.head upstream.freddy.aliases}"
            ];
          };
        };

        backend.buddy_passthrough = {
          mode = "tcp";
          server.buddy = {
            inherit (upstream.buddy) location;
            extraOptions = lib.concatStringsSep " " [
              "send-proxy-v2"
              "check"
              "ssl verify required"
              "ca-file /etc/ssl/certs/ca-bundle.crt"
              "check-sni ${builtins.head upstream.buddy.aliases}"
            ];
          };
        };

        frontend.https_terminator = {
          mode = "http";
          bind = [
            {
              location = "unix@/run/haproxy/local-https.sock";
              extraOptions = "ssl crt '@omega/fullchain.pem' alpn h2,http/1.1 accept-proxy";
            }
          ];
          option = [
            "httplog"
            "dontlognull"
            "http-server-close" # Allow server-side websocket connection termination
          ];
          compression = {
            algo = [
              "gzip"
              "deflate"
            ];
            type = [
              "text/html"
              "text/plain"
              "text/css"
              "text/javascript"
              "application/javascript"
              "application/x-javascript"
              "application/json"
              "application/ld+json"
              "application/wasm"
              "application/xml"
              "application/xhtml+xml"
              "application/rss+xml"
              "application/atom+xml"
              "text/xml"
              "text/markdown"
              "text/vtt"
              "text/cache-manifest"
              "text/calendar"
              "text/csv"
              "font/ttf"
              "font/otf"
              "image/svg+xml"
              "application/vnd.ms-fontobject"
            ];
          };

          acl.pictures_host = "req.hdr(host) -i ${service.pictures.hostname}";
          acl.pictures_alias = lib.concatMapStringsSep " || " (
            fqdn: "req.hdr(host) -i ${fqdn}"
          ) service.pictures.aliases;
          acl.status_host = "req.hdr(host) -i ${service.status.hostname}";
          acl.status_alias = lib.concatMapStringsSep " || " (
            fqdn: "req.hdr(host) -i ${fqdn}"
          ) service.status.aliases;

          # http/1.1 websocket detection
          #
          # NOTE; HTTP_2.0 is a built-in ACL
          #
          acl.is_websocket = "req.hdr(Upgrade) -i websocket";
          acl.is_upgrade = "req.hdr(Connection) -i upgrade";
          # http/2 websocket detection
          #
          # SEEALSO; global > h2-workaround-bogus-websocket-clients
          #
          acl.h2_ws_connect = "req.hdr(:method) -i CONNECT";
          acl.h2_ws_protocol = "req.hdr(:protocol) -i websocket";

          acl.host_is_omega = "hdr_beg(host) -i omega.";

          request = [
            "redirect prefix https://${service.pictures.hostname} code 302 if pictures_alias"
            "redirect prefix https://${service.status.hostname} code 302 if status_alias"

            "set-header X-Forwarded-Proto https"
            "set-header X-Forwarded-Host %[req.hdr(Host)]"
            "set-header X-Forwarded-Server %[hostname]"
            "set-header Strict-Transport-Security max-age=63072000"

            "set-var(txn.backend_name) str(immich_app) if pictures_host"
            "set-var(txn.backend_name) str(gatus_app) if status_host"

            # Websocket processing
            "set-var(txn.is_ws_h1) bool(true) if is_websocket is_upgrade !HTTP_2.0"
            "set-var(txn.is_ws_h2) bool(true) if h2_ws_connect h2_ws_protocol HTTP_2.0"
            "set-var(txn.is_ws) bool(true) if { var(txn.is_ws_h1) -m bool } or { var(txn.is_ws_h2) -m bool }"
            # short-circuit websockets
            "set-var(txn.backend_name) str(tls_to_buddy) if pictures_host { var(txn.is_ws) -m bool }"

            # transform omega.<domain> -> alpha.<domain> if websocket forwarding
            #
            # NOTE; HTTP header 'host' is updated before short-circuiting to the upstream service.
            #
            # NOTE; Documentation is unclear if this does the logical thing abstracted over both http1.1 and http2..
            # (Maybe need to use set-uri)
            "set-header Host %[req.hdr(host),regsub(^omega\.,alpha.,)] if { var(txn.is_ws) -m bool } pictures_host host_is_omega"

            # allow/deny large uploads similar to nginx's client_max_body_size (nginx default was 10M)
            "set-var(txn.max_body) str(\"10m\")"
            "set-var(txn.max_body) str(\"500m\") if pictures_host"

            # enforce payload size, units in bytes
            "set-var(txn.max_body_bytes) var(txn.max_body_str),bytes"
            "set-var(txn.body_size_diff) var(req.body_size),sub(txn.max_body_bytes)"
            "set-var(txn.cl_size_diff)   req.hdr_val(content-length),sub(txn.max_body_bytes)"
            "deny status 413 if { var(txn.body_size_diff) -m int gt 0 }"
            "deny status 413 if { var(txn.cl_size_diff) -m int gt 0 }"

            # reject if no backend set (optional hardening)
            "deny status 421 if !{ var(txn.backend_name) -m found }"
          ];
          backend = [
            "%[var(txn.backend_name)]"
          ];
        };

        backend.immich_app = {
          mode = "http";
          acl.host_is_omega = "hdr_beg(host) -i omega.";
          request = [
            # transform omega.<domain> -> alpha.<domain>
            #
            # NOTE; HTTP header 'host' is updated before delivering to varnish to have consistency between request and response.
            #
            # NOTE; Documentation is unclear if this does the logical thing abstracted over both http1.1 and http2..
            "set-header Host %[req.hdr(Host),regsub(^omega\.,alpha.,)]"
          ];
          server.varnish =
            assert lib.strings.hasInfix "varnish" service.pictures.location;
            {
              inherit (service.pictures) location;
              # Varnish endpoint!
              extraOptions = "send-proxy-v2 check";
            };
        };

        backend.status_app = {
          mode = "http";
          request = [ ];
          server.gatus = {
            inherit (service.status) location;
            extraOptions = "check";
          };
        };

        listen.tls_to_buddy = {
          description = "varnish community edition cannot connect upstream over TLS, so this is a leg of the hairpin (with proxy-v2)";
          mode = "http";
          bind = [
            {
              location = "unix@/run/haproxy-sockets/frontend.sock";
              extraOptions = "accept-proxy group haproxy-frontend mode 660";
            }
            # {
            #   # DEBUG
            #   location = "127.0.0.1:6666";
            # }
          ];
          extraConfig = ''
            no log
          '';

          server.buddy = {
            inherit (upstream.buddy) location;
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
            extraOptions = lib.concatStringsSep " " [
              "alpn h2,http/1.1"
              "send-proxy-v2"
              "check"
              "ssl verify required"
              "ca-file /etc/ssl/certs/ca-bundle.crt"
              "sni req.hdr(host)"
            ];
          };
        };
      };
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
