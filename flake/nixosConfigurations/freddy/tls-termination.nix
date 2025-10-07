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
    certs."omega.proesmans.eu".group = "nginx";
    certs."omega.proesmans.eu".reloadServices = [ config.systemd.services.nginx.name ];
  };

  # NOTE; Haproxy only does TLS muxing, it's not serving sites. Nginx is serving sites.
  services.haproxy =
    let
      # NOT YET
      # upstream.idm = rec {
      #   inherit (config.services.kanidm.serverSettings) origin bindaddress;
      #   aliases = [ "idm.proesmans.eu" ];
      #   # WARN; Domain and Origin are separate values from the effective DNS hostname.
      #   # REF; https://kanidm.github.io/kanidm/master/choosing_a_domain_name.html#recommendations
      #   hostname =
      #     assert origin == "https://idm.proesmans.eu";
      #     "alpha.idm.proesmans.eu";
      #   server = bindaddress;
      # };
      upstream.local-nginx = rec {
        aliases = [
          "wiki.proesmans.eu"
          "omega.wiki.proesmans.eu"
        ];
        hostname = "omega.proesmans.eu";
        server = "/run/nginx-sockets/virtualhosts.sock";
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
          use_backend passthrough_local_nginx if { ${
            lib.concatMapStringsSep " || " (sni: "req.ssl_sni -i ${sni}") (
              [ upstream.local-nginx.hostname ] ++ upstream.local-nginx.aliases
            )
          } }
          
          # anything else → drop
        #   default_backend drop_connection

        # backend drop_connection
        #   description drop unmatched tls connections
        #   mode tcp
        #   # immediately close on connect
        #   tcp-request connection reject

        backend passthrough_local_nginx
          description raw tcp passthrough with proxy protocol v1 (nginx community doesn\'t support v2)
          mode tcp
          server local_nginx unix@${upstream.local-nginx.server} check send-proxy
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
