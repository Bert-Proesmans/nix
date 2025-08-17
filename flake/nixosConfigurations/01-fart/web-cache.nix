{ lib, config, ... }:
{
  users.groups.varnish-forwarders = { };
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
        address = "/run/varnishd/frontend.sock";
        proto = "PROXY"; # Enable proxy V2 frames
        group = config.users.groups.varnish-forwarders.name;
      }
    ];
    config = ''
      vcl 4.1;
      # Based on: https://github.com/mattiasgeniar/varnish-6.0-configuration-templates/blob/master/default.vcl

      import std;

      # default backend: upstream server
      backend upstream_pictures {
          .host = "100.116.84.29";
          .port = "443";
          .proxy_header = 2;
          .host_header = "pictures.proesmans.eu";
      }

      # main request handling
      sub vcl_recv {
          # Implementing websocket support (https://www.varnish-cache.org/docs/4.0/users-guide/vcl-example-websockets.html)
          if (req.http.Upgrade ~ "(?i)websocket") {
            return (pipe);
          }

          # allow caching for static assets
          if (req.url ~ "\.(jpg|jpeg|png|gif|css|js)$") {
              return (hash);
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
      # ERROR; Extra group is required otherwise cannot create and chmod the frontend socket
      SupplementaryGroups = [ config.users.groups.varnish-forwarders.name ];
      # ERROR; Service directories are set to varnish_d_ upstream!
      CacheDirectory = "varnishd";
      CacheDirectoryMode = "0700";
    };
  };
}
