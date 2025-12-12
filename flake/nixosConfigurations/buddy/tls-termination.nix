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

  # Ensure no other modules enable nginx, only Haproxy is deployed!
  services.nginx.enable = lib.mkForce false;

  services.haproxy =
    let
      downstream.proxies.addresses = [
        # IP-Addresses of all hosts that proxy to us
        config.proesmans.facts."01-fart".host.tailscale.address
        config.proesmans.facts."02-fart".host.tailscale.address
      ];
      service.idm =
        assert config.services.kanidm.serverSettings.bindaddress == "127.0.0.1:8443";
        {
          # WARN; Domain and Origin are separate values from the effective DNS hostname.
          # REF; https://kanidm.github.io/kanidm/master/choosing_a_domain_name.html#recommendations
          hostname =
            assert config.services.kanidm.serverSettings.origin == "https://idm.proesmans.eu";
            "alpha.idm.proesmans.eu";
          aliases = [ "idm.proesmans.eu" ];
          location = "127.0.0.1:8443";
        };
      service.pictures =
        assert config.services.immich.host == "127.0.0.1";
        {
          hostname =
            assert config.services.immich.settings.server.externalDomain == "https://pictures.proesmans.eu";
            "alpha.pictures.proesmans.eu";
          aliases = [ "pictures.proesmans.eu" ];
          location = "${config.services.immich.host}:${toString config.services.immich.port}";
        };
      service.wiki = {
        # TODO; Reintroduce check after figuring out proper domain settings for outline
        hostname =
          #assert config.services.outline.publicUrl == "https://wiki.proesmans.eu";
          "alpha.wiki.proesmans.eu";
        aliases = [ "wiki.proesmans.eu" ];
        location = "127.0.0.1:${toString config.services.outline.port}";
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

        crt-stores.alpha.extraConfig = ''
          crt-base '${config.security.acme.certs."alpha.proesmans.eu".directory}'
          key-base '${config.security.acme.certs."alpha.proesmans.eu".directory}'
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
          option = [ ];
          # No logging here because duplicate logs introduced by hairpin into https_terminator
          extraConfig = ''
            no log
          '';

          acl.trusted_proxies = "src ${lib.concatStringsSep " " downstream.proxies.addresses}";
          request = [
            "connection expect-proxy layer4 if trusted_proxies"
            "inspect-delay 5s"
            "content accept if { req_ssl_hello_type 1 }"
          ];

          acl.kanidm_request = lib.concatMapStringsSep " || " (fqdn: "req.ssl_sni -i ${fqdn}") (
            [ service.idm.hostname ] ++ service.idm.aliases
          );
          backend = [
            {
              name = "passthrough_kanidm";
              condition = "kanidm_request";
            }
          ];

          server.local = "unix@/run/haproxy/local-https.sock send-proxy-v2";
        };

        frontend.https_terminator = {
          mode = "http";
          bind = [
            {
              location = "unix@/run/haproxy/local-https.sock";
              extraOptions = "ssl crt '@alpha/fullchain.pem' alpn h2,http/1.1 accept-proxy";
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
          acl.host_pictures = "req.hdr(host) -i ${service.pictures.hostname}";
          acl.alias_pictures = lib.concatMapStringsSep " || " (
            fqdn: "req.hdr(host) -i ${fqdn}"
          ) service.pictures.aliases;
          acl.host_wiki = "req.hdr(host) -i ${service.wiki.hostname}";
          acl.alias_wiki = lib.concatMapStringsSep " || " (
            fqdn: "req.hdr(host) -i ${fqdn}"
          ) service.wiki.aliases;
          request = [
            "redirect prefix https://${service.pictures.hostname} code 302 if alias_pictures"
            "redirect prefix https://${service.wiki.hostname} code 302 if alias_wiki"
            "set-header X-Forwarded-Proto https"
            "set-header X-Forwarded-Host %[req.hdr(Host)]"
            "set-header X-Forwarded-Server %[hostname]"
            "set-header Strict-Transport-Security max-age=63072000"

            "set-var(txn.backend_name) str(immich_app) if host_pictures"
            "set-var(txn.backend_name) str(outline_app) if host_wiki"

            # allow/deny large uploads similar to nginx's client_max_body_size (nginx default was 10M)
            "set-var(txn.max_body) str(\"10m\")"
            "set-var(txn.max_body) str(\"500m\") if host_pictures"

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
          option = [
            # adds X-Forwarded-For with client ip (non-standardized btw)
            "forwardfor"
          ];
          server.immich = {
            inherit (service.pictures) location;
            extraOptions = "check";
          };
          extraConfig = ''
            # Side-effect free use and reuse of upstream connections
            http-reuse safe
          '';
        };

        backend.outline_app = {
          mode = "http";
          option = [
            # adds forwarded with forwarding information (Preferred over forwardfor, IETF RFC7239)
            "forwarded"
          ];
          server.outline = {
            inherit (service.wiki) location;
            extraOptions = "check";
          };
          extraConfig = ''
            # Side-effect free use and reuse of upstream connections
            http-reuse safe
          '';
        };

        backend.passthrough_kanidm = {
          mode = "tcp";
          extraConfig = ''
            option tcp-check
            tcp-check send QUIT\r\n
          '';
          server.app = {
            inherit (service.idm) location;
            extraOptions = "send-proxy-v2 check check-ssl verify none";
          };
        };
      };
    };

  systemd.services.haproxy = {
    requires = [ "acme-alpha.proesmans.eu.service" ];
    after = [ "acme-alpha.proesmans.eu.service" ];
  };

}
