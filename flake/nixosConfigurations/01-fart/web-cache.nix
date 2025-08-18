{ lib, config, ... }:
{
  # Allow r/w access to haproxy frontend socket
  users.groups.haproxy-frontend.members = [ "varnish" ];

  services.varnish = {
    enable = true;
    # ERROR; Varnish verifies upstream IP reachability.. during build time :/
    enableConfigCheck = false;
    extraModules = [ ];
    extraCommandLine = lib.concatStringsSep " " [
      # NOTE; In-memory cache (default)
      # HELP; Could tweak depending on observed memory pressure, ofcourse you want this
      # as high as possible but I haven't read about effects yet.
      "-s default,100m"
      # cache on disk, as preallocated file
      "-s file,/var/cache/varnishd/cachefile.bin,10G"
    ];
    listen = [
      {
        name = "local_unix";
        address = "/run/varnish-sockets/frontend.sock";
        proto = "PROXY"; # Enable proxy V2 frames
        group = config.users.groups.varnish-frontend.name;
        mode = "660";
      }
    ];
    config = ''
      vcl 4.1;
      # Based on: https://github.com/mattiasgeniar/varnish-6.0-configuration-templates/blob/master/default.vcl

      import std;

      backend upstream_pictures {
        # ERROR; Varnish community does NOT support tls upstream connections!
        # NOTE; Varnish enterprise does..
        .path = "/run/haproxy-sockets/frontend.sock";  # run it back to haproxy
        .proxy_header = 2;
      }

      sub vcl_recv {
        if (req.http.host == "omega.pictures.proesmans.eu") {
          # rewrite host for backend fetch 
          # WARN; assumes pretty brittle setup, needs iteration
          set req.http.X-Orig-Host = req.http.host;
          set req.http.host = "alpha.pictures.proesmans.eu";
        }

        # Implementing websocket support (https://www.varnish-cache.org/docs/4.0/users-guide/vcl-example-websockets.html)
        if (req.http.Upgrade ~ "(?i)websocket") {
          return (pipe);
        }

        # allow caching for static assets
        if (req.url ~ "\.(jpg|jpeg|png|gif|css|js)$") {
            return (hash);
        }
      }

      sub vcl_backend_fetch {
        if (bereq.http.X-Orig-Host) {
            set bereq.http.host = "alpha.pictures.proesmans.eu";
        }
      }

      sub vcl_backend_response {
        # cache assets in memory and disk
        if (bereq.url ~ "\.(jpg|jpeg|png|gif|css|js)$") {
          set beresp.ttl = 1h;             # cache for 1 hour
          set beresp.grace = 30m;          # serve stale while revalidating
        }
      }

      sub vcl_deliver {
        if (resp.http.Location && req.http.X-Orig-Host) {
          set resp.http.Location = regsub(resp.http.Location, "alpha.pictures.proesmans.eu", req.http.X-Orig-Host);
        }

        # optional: add header to see if served from cache
        if (obj.hits > 0) {
          set resp.http.X-Cache = "HIT";
        } else {
          set resp.http.X-Cache = "MISS";
        }
      }
    '';
  };

  systemd.services.varnish = {
    serviceConfig = {
      # ERROR; Service directories are set to varnish_d_ upstream!
      CacheDirectory = "varnishd";
      CacheDirectoryMode = "0700";
    };
  };

  # Add members to group varnish-frontend for r/w access to /run/varnish-sockets/frontend.sock
  users.groups.varnish-frontend.members = [ "varnish" ];
  systemd.tmpfiles.settings."50-varnish-sockets" = {
    "/run/varnish-sockets".d = {
      user = "varnish";
      group = config.users.groups.varnish-frontend.name;
      mode = "0755";
    };
  };
}
