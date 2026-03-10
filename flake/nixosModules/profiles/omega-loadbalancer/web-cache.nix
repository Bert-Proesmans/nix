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
      # open port for admin interface (connect with varnishadm)
      # SEEALSO; systemd.services.varnish.serviceConfig.IPAddressAllow
      # "-T 127.0.0.1:42057" # Default
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
        .path = "/run/haproxy/forward_to_freddy.sock";  # run it back to haproxy
        .proxy_header = 2;

        .connect_timeout        = 10s;   # How long to wait for a backend connection?
        .first_byte_timeout     = 65s;   # How long to wait before we receive a first byte from our backend?
        .between_bytes_timeout  = 2s;    # How long to wait between bytes received from our backend?

        .probe = {
          # Debug with; varnishadm backend.list
          .request =
            "GET /api/server/ping HTTP/1.1"
            "Host: omega.pictures.proesmans.eu"
            "Connection: close"
            "User-Agent: Varnish Health Probe";

          .interval  = 5s;  # check the health of each backend every 5 seconds
          .timeout   = 10s; # timing out after 10 seconds.
          .window    = 10;   # If 8 out of the last 10 polls succeeded the backend is considered healthy
          .threshold = 8;
          .initial = 6;
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

          # Fix the host header data to always be omega.pictures.proesmans.eu, which is the right (only) hostname
          # for this upstream.
          # ERROR; This change happens as early as possible to not interfere with hashing/retrieval logic
          set req.http.Host = "omega.pictures.proesmans.eu";
          set req.http.X-Forwarded-Host = "omega.pictures.proesmans.eu";
        } else {
          # NOTE; No caching, immediate return
          return (synth(404));
        }

        # --- Skip caching ---
        if (req.method != "GET" && req.method != "HEAD") {
          return (pass);
        }
        
        if(req.http.X-Backend == "pictures" && req.url ~ "^/api/server/ping") {
          return (pass);
        }

        if (req.http.Range) {
          # NOTE; Varnish will fire a normal (full-range) request to the backend to cache the entire object. Clients will be able
          # to request specific ranges for as long as the object is in cache.
          # WARN; The cache object is locked while streaming to the first requesting client. I'm not sure if/how this can be fixed.
          # return (pass);
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
        
        # No grace timer
        # SEEALSO sub vcl_deliver
        set req.http.grace = "none";

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

      #
      # Debug requests with; varnishlog -g request -q 'ReqUrl eq "/<path to thing>"'
      # eg varnishlog -g request -q 'ReqUrl eq "/api/server/media-types"'
      # eg varnishlog -g request -q 'ReqUrl ~ "video/playback$"'
      # eg varnishlog -g request -q 'RespStatus eq 206'
      #

      sub vcl_hit {
        # Called when a cache lookup is succesful..
        #
        # REF; https://vinyl-cache.org/docs/7.7/reference/states.html
        # REF; https://vinyl-cache.org/docs/7.7/users-guide/vcl-grace.html

        # obj.ttl + obj.grace is _always_ > 0s here
        
        if (obj.ttl <= 0s) {
          # Grace timer has started running down
          set req.http.grace = "limited";
        } else {
          # Grace timer still needs to start
          set req.http.grace = "full";  
        }

        # builtin.vcl proceeds to deliver..
      }

      sub vcl_miss {
        # Called when
        # - hit-for-miss
        # - grace period has run out (no background fetch running)
        #
        # REF; https://vinyl-cache.org/docs/7.7/reference/states.html
        # REF; https://vinyl-cache.org/docs/7.7/users-guide/vcl-grace.html

        if (!req.is_hitmiss) {
          # Grace has run out
          set req.http.grace = "empty";
        }

        # builtin.vcl proceeds to fetch..
      }

      sub vcl_backend_fetch {
        # Reinsertion of fixed up headers should happen here logically (right before actual fetch)
        #
        # REF; https://vinyl-cache.org/docs/7.7/reference/states.html


        if (bereq.http.X-Upstream-Cookies) {
          # Cookies that were dropped are likely required when fetching upstream resources
          set bereq.http.cookie = bereq.http.X-Upstream-Cookies;
          unset bereq.http.X-Upstream-Cookies;
        }

        # builtin.vcl proceeds to fetch..
      }

      sub vcl_backend_response {
        # SEEALSO; sub vcl_recv

        if(beresp.status == 404) {
          # Temporarily cache resource not found, it's a retryable state.
          set beresp.ttl = 1m;
          set beresp.grace = 10m;
          return (deliver);
        }

        # NOTE; There are no defined status codes from 600 and beyond
        if (beresp.status >= 500) {
          if (bereq.is_bgfetch) {
            # The client earlier received a cached object (grace), and that flow triggered this background update asynchronously.
            # If the response is 5xx we have to abandon, otherwise the previously cached object would be erased and
            # replaced with the current response.
            # WARN; 5xx response is also _just_ a response
            return (abandon);
          }

          # ERROR; Setting uncacheable to true stores a hit-for-miss object which _does not_ coalesce requests and forces new backend
          # requests for each frontend request! This does not shed load from the server nor improve latency!
          # set beresp.uncacheable = true; # Doesn't work as intuitive expectation

          # Temporarily cache _generic_ backend error responses.
          set beresp.ttl = 30s;
          # NOTE; The error keyword does the same as "synth", but it's explicitly mentioned that the production of "error" can
          # become cached.
          return (error(beresp.status));
        }

        # Attempt a default TTL otherwise a hit-for-miss is served.
        set beresp.ttl = 10s;
        # Allow serving stale content in case the backend goes down.
        # The cache will still attempt to revalidate these objects at client request.
        set beresp.grace = 1m;

        if (bereq.http.Range) {
          # Response containers data for requested range. Disable store-and-forward, stream instantly instead.
          # NOTE; do_stream = true _does not_ skip caching the object! To skip cache entirely it's still required to return(pass).
          set beresp.do_stream = true;
        }

        if (beresp.http.ETag || beresp.http.Last-Modified) {
          # Response has appropriate headers for efficient stale checks.
          # Because updates are efficiently queried the (potentially large) object can be kept longer in cache to alleviate
          # server bandwidth.
          set beresp.keep = 1w;
        }

        # NOTE; Step optimized regex! DO NOT "IMPROVE"
        if (bereq.http.Content-type ~ "^(((image|video|font)/.+)|application/javascript|text/css).*$") {
          # Force enable caching, do not follow server directives
          unset beresp.http.cache-control;
          unset beresp.http.Set-Cookie;
          set beresp.ttl = 2d;
        }

        if (bereq.http.X-Backend == "pictures" && bereq.url ~ "^/api/assets/") {
          set beresp.ttl = 1m;
          set beresp.grace = 1h;

          # Force enable caching because immich returns HTTP "cache-control: private" for all assets
          unset beresp.http.cache-control;
          unset beresp.http.Set-Cookie;
        }

        # These are specifically the media files!
        if (bereq.http.X-Backend == "pictures" && 
            (bereq.url ~ "^/api/assets/[^/]+/(thumbnail|original|video)" || bereq.url ~ "^/_app/")
        ) {
          set beresp.ttl = 1w; # serving from cache
          set beresp.grace = 1d; # serving stale data from cache with background refresh at next client request

          # Force enable caching because immich returns HTTP "cache-control: private"
          unset beresp.http.cache-control;
          unset beresp.http.Set-Cookie;
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

      sub vcl_synth {
        # Up to Varnish current (v7.7) only action 'deliver' adds a http-header 'via'.
        # Since Varnish v7.2 there is a via header added/appended to the request before vcl_recv, so we can reuse that header value
        # copied to the response.
        set resp.http.via = req.http.via;
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
      IPAddressAllow = "localhost";
    };
  };
}
