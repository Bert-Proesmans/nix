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
    certs."omega.proesmans.eu" = {
      group = config.users.groups.nginx.name;
      reloadServices = [ config.systemd.services.nginx.name ];
    };

    certs."omega.passwords.proesmans.eu" = {
      group = config.users.groups.haproxy.name;
      reloadServices = [
        config.systemd.services.haproxy.name
      ];
    };
  };

  # NOTE; Haproxy does TLS muxing, and only TLS termination for the passwords app!
  # Nginx is serving sites.
  services.haproxy =
    let
      downstream.proxies.addresses = [
        # IP-Addresses of all hosts that proxy to us
        # NOTE; Using the tailscale address to tunnel between nodes.
        # Tailscale should link over oracle subnet.
        config.proesmans.facts."01-fart".host.tailscale.address
        config.proesmans.facts."02-fart".host.tailscale.address
      ];

      upstream.local-nginx = {
        aliases = [
          "wiki.proesmans.eu"
          "omega.wiki.proesmans.eu"
        ];
        location = "/run/nginx-sockets/virtualhosts.sock";
      };

      service.idm =
        assert config.services.kanidm.serverSettings.bindaddress == "127.0.0.1:8443";
        {
          # WARN; Domain and Origin are separate values from the effective DNS hostname.
          # REF; https://kanidm.github.io/kanidm/master/choosing_a_domain_name.html#recommendations
          hostname =
            assert config.services.kanidm.serverSettings.origin == "https://idm.proesmans.eu";
            "omega.idm.proesmans.eu";
          aliases = [ "idm.proesmans.eu" ];
          location = "127.0.0.1:8443";
        };
      service.passwords =
        assert config.services.vaultwarden.config.ROCKET_ADDRESS == "127.0.0.1";
        {
          hostname =
            assert config.services.vaultwarden.config.DOMAIN == "https://passwords.proesmans.eu";
            "omega.passwords.proesmans.eu";
          aliases = [ "passwords.proesmans.eu" ];
          location = "127.0.0.1:${toString config.services.vaultwarden.config.ROCKET_PORT}";
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
            # log stdout format raw local0 notice
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

          acl.trusted_proxies = "src ${lib.concatStringsSep " " downstream.proxies.addresses}";
          request = [
            "connection expect-proxy layer4 if trusted_proxies"
            "inspect-delay 5s"
            "content accept if { req_ssl_hello_type 1 }"
          ];

          acl.kanidm_request = lib.concatMapStringsSep " || " (fqdn: "req.ssl_sni -i ${fqdn}") (
            [ service.idm.hostname ] ++ service.idm.aliases
          );
          acl.local_nginx_request = lib.concatMapStringsSep " || " (
            fqdn: "req.ssl_sni -i ${fqdn}"
          ) upstream.local-nginx.aliases;

          backend = [
            {
              name = "passthrough_kanidm";
              condition = "kanidm_request";
            }
            {
              name = "passthrough_local_nginx";
              condition = "local_nginx_request";
            }
          ];

          server.local = "unix@/run/haproxy/local-https.sock send-proxy-v2";
        };

        backend.passthrough_kanidm = {
          mode = "tcp";
          extraConfig = ''
            option tcp-check
            tcp-check send QUIT\r\n
          '';
          server.app = {
            inherit (service.idm) location;
            extraOptions = "send-proxy-v2 check check-sni ${service.idm.hostname} check-ssl verify none";
          };
        };

        backend.passthrough_local_nginx = {
          mode = "tcp";
          server.app = {
            inherit (upstream.local-nginx) location;
            extraOptions = "send-proxy check";
          };
        };

        crt-stores.omega-passwords.extraConfig = ''
          crt-base '${config.security.acme.certs."omega.passwords.proesmans.eu".directory}'
          key-base '${config.security.acme.certs."omega.passwords.proesmans.eu".directory}'
          # NOTE; Wildcard + multiple domains certificate
          load crt 'fullchain.pem' key 'key.pem'
        '';

        frontend.https_terminator = {
          mode = "http";
          bind = [
            {
              location = "unix@/run/haproxy/local-https.sock";
              extraOptions = "ssl crt '@omega-passwords/fullchain.pem' alpn h2,http/1.1 accept-proxy";
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

          acl.host_passwords = "req.hdr(host) -i ${service.passwords.hostname}";
          acl.alias_passwords = lib.concatMapStringsSep " || " (
            fqdn: "req.hdr(host) -i ${fqdn}"
          ) service.passwords.aliases;
          request = [
            "redirect prefix https://${service.passwords.hostname} code 302 if alias_passwords"
            "set-header X-Forwarded-Proto https"
            "set-header X-Forwarded-Host %[req.hdr(Host)]"
            "set-header X-Forwarded-Server %[hostname]"
            "set-header Strict-Transport-Security max-age=63072000"

            "set-var(txn.backend_name) str(vaultwarden_app) if host_passwords"

            # allow/deny large uploads similar to nginx's client_max_body_size (nginx default was 10M)
            "set-var(txn.max_body) str(\"10m\")"
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

        backend.vaultwarden_app = {
          mode = "http";
          option = [
            # adds X-Forwarded-For with client ip (non-standardized btw)
            "forwardfor"
          ];
          server.vaultwarden = {
            inherit (service.passwords) location;
            extraOptions = "check";
          };
          extraConfig = ''
            # Side-effect free use and reuse of upstream connections
            http-reuse safe
          '';
        };
      };
    };

  systemd.services.haproxy = {
    requires = [ "acme-omega.passwords.proesmans.eu.service" ];
    after = [ "acme-omega.passwords.proesmans.eu.service" ];
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
    params.haproxy = {
      # Defaults are used.
      # Use 'params.nginx.path' to retrieve the parameters.
    };
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
