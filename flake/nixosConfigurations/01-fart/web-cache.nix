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
      import directors; # Upstream balancer
      import cookie; # Cookie string manipulation

      backend upstream_pictures {
        # ERROR; Varnish community does NOT support tls upstream connections!
        # NOTE; Varnish enterprise does..
        .path = "/run/haproxy-sockets/frontend.sock";  # run it back to haproxy
        .proxy_header = 2;

        .first_byte_timeout     = 300s;   # How long to wait before we receive a first byte from our backend?
        .connect_timeout        = 5s;     # How long to wait for a backend connection?
        .between_bytes_timeout  = 2s;     # How long to wait between bytes received from our backend?

        .probe = {
          #.url = "/"; # short easy way (GET /)
          
          # Debug with; varnishadm backend.list
          .request =
            "GET / HTTP/1.1"
            "Host: alpha.pictures.proesmans.eu"
            "Connection: close"
            "User-Agent: Varnish Health Probe";

          .interval  = 5s; # check the health of each backend every 5 seconds
          .timeout   = 1s; # timing out after 1 second.
          .window    = 5;  # If 3 out of the last 5 polls succeeded the backend is considered healthy, otherwise it will be marked as sick
          .threshold = 3;
        }
      }

      sub vcl_recv {
        # Parametrize backend selection to abstract later procedures
        # ERROR; No string, but backend type value
        set req.backend_hint = upstream_pictures;

        # Remove the proxy header (see https://httpoxy.org/#mitigate-varnish)
        unset req.http.proxy;
        
        # Normalize the query arguments
        set req.url = std.querysort(req.url);

        # --- Some generic URL manipulation ---
        # Strip hash, improving cache hitrate
        if (req.url ~ "\#") {
          set req.url = regsub(req.url, "\#.*$", "");
        }

        # Strip a trailing ? if it exists, improving cache hitrate
        if (req.url ~ "\?$") {
          set req.url = regsub(req.url, "\?$", "");
        }

        # --- Some generic cookie manipulation --
        # builtin.vcl _SKIPS_ hashing when cookie header is set!
        #
        # Don't manipulate empty cookies
        if (req.http.cookie !~ "^\s*$") {
          cookie.parse(req.http.cookie);
          # Global cookies to be gone!
          set req.http.cookie = cookie.get_string();

          if(req.url ~ "^/api/assets/") {
            # Ignore all cookies for immich assets, but keep them for the backend request on cache-miss.
            # SECURITY; This path must use secure randomly generated asset ids to not leak assets!
            #
            # WARN; Upstream requires following cookies; immich_access_token,immich_auth_type,immich_is_authenticated
            set req.http.X-Upstream-Cookies = req.http.cookie;
            unset req.http.cookie;
          }          
        }

        # Are there cookies left with only spaces or that are empty?
        if (req.http.cookie ~ "^\s*$") {
          unset req.http.cookie;
        }

        if (std.healthy(req.backend_hint)) {
          // Prevent thundering herd on new/stale requests by allowing request coalescing
          // REF; https://varnish-cache.org/docs/trunk/users-guide/increasing-your-hitrate.html#cache-misses
          set req.grace = 10s;
        }

        # Set headers for request-response debugging
        set req.http.grace = "none"; # DEBUG, see sub vcl_hit

        # builtin.vcl handles HTTP host normalization
        # builtin.vcl handles HTTP method filtering
        # builtin.vcl handles HTTP authorization filtering
        # Proceed with builtin default action
      }

      sub vcl_pipe {
        # Do as builtin
      }

      sub vcl_pass {
        # Do as builtin
      }

      sub vcl_hash {        
        if (req.http.Cookie) {
          # hash cookies for requests that have them
          # NOTE; Prevents exfiltration of data without authentication
          hash_data(req.http.Cookie);
        }

        if (req.http.X-Forwarded-Proto) {
          # Cache the HTTP vs HTTPs separately
          # NOTE; Prevents exfiltration of data without secure protocol
          # TODO; Attempt to cache thumbnail assets even though a valid token is required!
          hash_data(req.http.X-Forwarded-Proto);
        }

        if (req.http.X-Upstream-Cookies) {
          # Add dropped cookies again to fetch upstream resources correctly
          set req.http.cookie = req.http.X-Upstream-Cookies;
          unset req.http.X-Upstream-Cookies;
        }

        # builtin.vcl performs host+url hashing
        # Proceed with builtin default action
      }

      sub vcl_hit {
        # Called when a cache lookup is succesful..

        if (obj.ttl >= 0s) {
          # Object still fresh (within cache expiry time)
          return (deliver);
        }

        # builtin.vcl does nothing..
      }

      sub vcl_miss {
        # Called when an asynchronous backend request has fired!
        # REF; https://varnish-cache.org/docs/trunk/users-guide/vcl-grace.html#the-effect-of-grace-and-keep

        # TODO; Better understand caching mechanics, lots of changes in >=v6.0 with differences in flows and outcome.

        # if (std.healthy(req.backend_hint)) {
        #   if (obj.ttl + 10s > 0s) {
        #     # Prevent thundering herd when object expires, an asynchronous request to upstream is ongoing
        #     set req.http.grace = "normal(limited)";
        #     return (deliver);
        #   }
        # } else {
        #   if (obj.ttl + obj.grace > 0s) {
        #     # Keep returning data for full grace period
        #     set req.http.grace = "full";
        #     return (deliver);
        #   }  
        # }

        # builtin.vcl does nothing..
      }

      sub vcl_backend_response {
        # SEEALSO; sub vcl_recv
        # NOTE; Step optimized regex! DO NOT "IMPROVE"
        if (bereq.http.Content-type ~ "^(((image|video|font)/.+)|application/javascript|text/css).*$") {
          # Force enable caching, do not follow server directives
          unset beresp.http.cache-control;
          unset beresp.http.Set-Cookie;
          set beresp.ttl = 6h;
        }

        if (bereq.url ~ "^/api/assets/") {
          # Force enable caching because immich returns HTTP "cache-control: private"
          unset beresp.http.cache-control;
          unset beresp.http.Set-Cookie;
          set beresp.ttl = 24h;
        }

        if (beresp.status == 500 || beresp.status == 502 || beresp.status == 503 || beresp.status == 504) {
          # Don't cache 50x responses
          return (abandon);
        }

        # Allow stale content, in case the backend goes down.
        # make Varnish keep all objects for 6 hours beyond their TTL
        set beresp.grace = 6h;

        if (beresp.http.ETag || beresp.http.Last-Modified) {
          # Response has appropriate headers for efficient stale checks.
          # Allow for up to 24 additional hours for upstream checks.
          set beresp.keep = 24h;
        }

        # builtin.vcl handles HTTP content-range normalization
        # 
        # The next parts are about intelligent hit-for-miss.
        # REF; https://varnish-cache.org/docs/trunk/users-guide/increasing-your-hitrate.html#hit-for-miss
        # builtin.vcl handles HTTP cache control
        # builtin.vcl skips caching with HTTP vary header == '*'
        # builtin.vcl skips caching with HTTP set-cookie != '<empty>'
        #
        # Proceed with builtin default action
      }

      sub vcl_deliver {
        # Add client-side debugging values
        set resp.http.X-Cache = "MISS";
        set resp.http.X-Varnish-Grace = req.http.grace;

        if (obj.hits > 0) {
          # Returned object came from cache
          set resp.http.X-Cache = "HIT";
        }

        # builtin.vcl does nothing..
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
