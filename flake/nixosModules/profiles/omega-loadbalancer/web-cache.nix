{ lib, config, ... }:
{
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
        group = config.users.groups.varnish.name;
        mode = "660";
      }
    ];
    config = ''
      vcl 4.1;
      # Based on: https://github.com/mattiasgeniar/varnish-6.0-configuration-templates/blob/master/default.vcl

      import std;
      import directors; # Upstream balancer
      import cookie; # Cookie string manipulation

      backend pictures {
        # ERROR; Varnish community does NOT support tls upstream connections!
        # NOTE; Varnish enterprise does..
        # .path = "/run/haproxy/forward_to_buddy.sock";  # run it back to haproxy
        .path = "/run/haproxy/forward_to_freddy.sock";  # run it back to haproxy
        .proxy_header = 2;

        .connect_timeout        = 10s;   # How long to wait for a backend connection?
        .first_byte_timeout     = 65s;   # How long to wait before we receive a first byte from our backend?
        .between_bytes_timeout  = 2s;    # How long to wait between bytes received from our backend?

        .probe = {
          # Debug with; varnishadm backend.list
          .request =
            "GET /api/server/ping HTTP/1.1"
            "Host: alpha.pictures.proesmans.eu"
            "Connection: close"
            "User-Agent: Varnish Health Probe";

          .interval  = 5s;  # check the health of each backend every 5 seconds
          .timeout   = 10s; # timing out after 1 second.
          .window    = 5;   # If 2 out of the last 5 polls succeeded the backend is considered healthy, otherwise it will be marked as sick
          .threshold = 2;
        }
      }

      sub vcl_recv {
        # Remove the proxy header (see https://httpoxy.org/#mitigate-varnish)
        unset req.http.proxy;

        if (req.http.X-Forwarded-Host ~ "^\s*$") {
          return (synth(404));
        }

        # Normalize values that we're matching for accurate results
        if (req.http.url ~ "[[:upper:]]") {
          set req.http.url = req.http.url.lower();
        }

        if (req.http.X-Forwarded-Host ~ "[[:upper:]]") {
          set req.http.X-Forwarded-Host = req.http.X-Forwarded-Host.lower();
        }

        # --- Backend selection ---
        if (req.http.X-Forwarded-Host == "pictures.proesmans.eu" || 
            req.http.X-Forwarded-Host ~ "\.pictures\.proesmans\.eu$") {
          set req.http.X-Backend = "pictures";
          set req.backend_hint = pictures;

          # Fix the host header data to always be alpha.pictures.proesmans.eu, which is the right (only) hostname
          # for this upstream.
          # ERROR; This change happens as early as possible to not interfere with hashing/retrieval logic
          set req.http.Host = "alpha.pictures.proesmans.eu";
          set req.http.X-Forwarded-Host = "alpha.pictures.proesmans.eu";
        } else {
          return (synth(404));
        }

        # --- Skip caching status endpoints ---
        if(req.url ~ "^/status") {
          return (pass);
        }
        if(req.http.X-Backend == "pictures" && req.url ~ "^/api/server/ping") {
          return (pass);
        }

        # --- Some generic URL manipulation ---
        # Normalize the query arguments
        set req.url = std.querysort(req.url);
        
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
          #
          # Manipulate cookie values here using the cookie module
          #
          set req.http.cookie = cookie.get_string();

          if(req.http.X-Backend == "pictures" && (req.url ~ "^/api/assets/" || req.url ~ "^/_app/")) {
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
        set req.http.grace = "none"; # DEBUG, see sub vcl_deliver

        # builtin.vcl handles HTTP host normalization
        # builtin.vcl handles HTTP method filtering
        # builtin.vcl handles HTTP authorization filtering
        # Proceed with builtin default action
      }

      sub vcl_pipe {
        # Do as builtin
      }

      sub vcl_pass {
        # builtin.vcl does nothing..
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
          hash_data(req.http.X-Forwarded-Proto);
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

        # builtin.vcl proceeds to deliver..
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

        # builtin.vcl proceeds to fetch..
      }

      sub vcl_backend_fetch {
        # Reinsertion of fixed up headers should happen here logically (right before actual fetch)
        # REF; https://varnish-cache.org/docs/7.7/reference/states.html


        if (bereq.http.X-Upstream-Cookies) {
          # Cookies that were dropped are likely required when fetching upstream resources
          set bereq.http.cookie = bereq.http.X-Upstream-Cookies;
          unset bereq.http.X-Upstream-Cookies;
        }

        # builtin.vcl proceeds to fetch..
      }

      sub vcl_backend_response {
        # SEEALSO; sub vcl_recv
        if (beresp.status == 500 || beresp.status == 502 || beresp.status == 503 || beresp.status == 504) {
          # Don't cache 50x responses
          return (abandon);
        }

        # Attempt a default TTL otherwise a hit-for-miss is served.
        set beresp.ttl = 10s;
        # Allow serving stale content in case the backend goes down.
        # The cache will still attempt to revalidate these objects at client request.
        set beresp.grace = 1m;

        if (beresp.http.ETag || beresp.http.Last-Modified) {
          # Response has appropriate headers for efficient stale checks.
          # 'Keep' will not offer the object to the client, but ask the server for update metadata instead of the full object.
          set beresp.keep = 1w;
        }

        # NOTE; Step optimized regex! DO NOT "IMPROVE"
        if (bereq.http.Content-type ~ "^(((image|video|font)/.+)|application/javascript|text/css).*$") {
          # Force enable caching, do not follow server directives
          unset beresp.http.cache-control;
          unset beresp.http.Set-Cookie;
          if (beresp.ttl <= 0s) {
            set beresp.ttl = 2d;
          }
        }

        # WARN; Other items are also returned outside of media underneath /api/assets/ !!
        if (bereq.http.X-Backend == "pictures" && bereq.url ~ "^/api/assets/") {
          # Force enable caching because immich returns HTTP "cache-control: private"
          unset beresp.http.cache-control;
          unset beresp.http.Set-Cookie;
          set beresp.ttl = 10s; # serving from cache
          set beresp.grace = 1h; # serving from cache with attempting refresh on client request
        }

        # These are specifically the media files!
        if (bereq.http.X-Backend == "pictures" && bereq.url ~ "^/api/assets/[^/]+/(thumbnail|original)") {
          # Force enable caching because immich returns HTTP "cache-control: private"
          unset beresp.http.cache-control;
          unset beresp.http.Set-Cookie;
          set beresp.ttl = 1w; # serving from cache
          set beresp.grace = 1w; # serving from cache with attempting refresh on client request
          set beresp.keep = 1w; # no serving, best case refresh if no metadata change
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
    # NOTE; I'm currently not sure if implementing varnish reload myself is worth the time.
    # Varnish does not guarantee cache consistency between restarts, so every configuration update followed by service restart
    # clears all cached data. A service (or config) reload persists the cached data instead.

    serviceConfig = {
      SupplementaryGroups = [
        # Allow varnish access to /run/haproxy/forward_to_buddy.sock
        config.users.groups.haproxy.name
      ];

      # ERROR; Service directories are set to varnish_d_ upstream!
      CacheDirectory = "varnishd";
      CacheDirectoryMode = "0700";

      # Varnish' default shared memory segment bucket is 80 megabytes (see varnishd -l).
      # The system default memory lock limit is 8 megabyte, increase the maximum memory lock amount to not get the cache swapped out below us.
      #
      # NOTE; Limit is a bit higher than the default vsl space (80m) to allow for other memory segment types to be locked too.
      # REF; https://github.com/varnishcache/pkg-varnish-cache/blob/1f0d212dc45065f38bd80ac57fe22773a20a0595/systemd/varnish.service
      LimitMEMLOCK = "100M";

      # Restrict varnish from doing anything outside of muxing between unix sockets
      RestrictAddressFamilies = lib.mkForce [
        "AF_UNIX"
        # WORKAROUND; Varnish tries to find out default TCP socket parameters.
        # Allow AF_INET but deny any actual IP communication. (see IPAddressDeny below)
        #
        # REF; https://github.com/varnishcache/varnish-cache/blob/6e4e674b9bef2e58eab3d755856244e2c9541068/bin/varnishd/mgt/mgt_param_tcp.c#L74-L76
        "AF_INET"
      ];
      IPAddressDeny = "any"; # WORKAROUND
    };
  };
}
