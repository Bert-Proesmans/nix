{ lib, ... }:
{
  # Resolve domain names using 1. hosts file, then 2. resolver (local routedns)
  # NOTE; These options all point to a pluggable Name Service Switch (NSS) compatible module.
  #   - "files" answers using data from the hosts file
  #   - "myhostname" answers using systemd (hostnamectl, but also /etc/hostname etc)
  #   - "dns" answers using queries over DNS. the /etc/resolv.conf file defines how DNS queries are created
  system.nssDatabases.hosts = lib.mkForce [
    "files"
    "myhostname"
    "dns"
  ];

  # Setup working local DNS resolve
  networking.resolvconf.enable = true;
  networking.resolvconf.extraConfig = ''
    name_servers='127.0.0.53'
  '';
  # Disable resolved (systemd) to free up the DNS port(53) on loopback.
  services.resolved.enable = false;

  # Servicing structure
  # [INGRESS] -> Divert local or not -> ++local / **remote
  # ++local -> Resolve /etc/hosts -> **remote
  # **remote -> Response cache component -> TTL modifier -> Client rate limiter -> *
  # * -> Query blocklist -> Query response blocklist -> IP response blocklist -> *
  # * -> Upstream rate limiter -> Upstream failover -> [EGRESS]
  services.routedns = {
    # WARN; The service will throw warnings about blocklists not being cached. These warnings will suspiciously look
    # like errors. It just means that routedns will download the requested files.
    # NOTE; The configuration is setup to fail the service if the blocklists cannot be downloaded!
    enable = true;

    # SOURCE; https://github.com/folbricht/routedns/blob/70bdfc29d9288eac1bf34d3b3b9ace37fcd1a393/cmd/routedns/example-config/use-case-6.toml
    # RouteDNS config with caching and multiple blocklists that are loaded and refreshed from remote
    # locations daily. DNS queries are received on the local network, filtered, cached and forwarded
    # over DoT to upstream resolvers.
    settings = {

      bootstrap-resolver = {
        # Since this configuration references remote blocklists, hostname resolution for them could
        # fail on startup if the system uses RouteDNS as only source of name resolution. Using
        # a bootstrap-resolver defines how hostnames in blocklists or resolvers should be looked up.
        # Here, use Cloudflare DNS-over-TLS to lookup blocklist addresses.
        address = "1.1.1.1:853";
        protocol = "dot";
      };

      listeners = {
        # Listeners for the local network. Can be restricted further to specific networks
        # with the "allowed-net" option
        network-udp = {
          address = ":53";
          protocol = "udp";
          resolver = "local_or_not";
        };
        network-tcp = {
          address = ":53";
          protocol = "tcp";
          resolver = "local_or_not";
        };
      };

      routers.local_or_not = {
        routes = [
          ({
            source = "127.0.0.0/8";
            resolver = "hosts-override";
          })
          ({
            source = "::1/128";
            resolver = "hosts-override";
          })
          ({ resolver = "cache"; })
        ];
      };

      groups = {
        # Answer with hosts file override!
        hosts-override = {
          type = "blocklist-v2";
          resolvers = [ "cache" ];
          # NOTE; Refresh is also required for local files!
          blocklist-refresh = 300; # 5 minutes
          blocklist-source = [
            ({
              format = "hosts";
              source = "/etc/hosts";
            })
          ];
        };

        # Cache resolve responses
        cache = {
          type = "cache";
          resolvers = [ "ttl-update" ];
          cache-negative-ttl = 60; # 1 minute
          backend.type = "memory";
          backend.size = 8192; # units
        };

        # Clamp TTL values in responses
        ttl-update = {
          type = "ttl-modifier";
          resolvers = [ "rate-limit-client" ];
          ttl-min = 1800; # 30 Minutes
          ttl-max = 43200; # 12 Hours
        };

        # Rate limit requests for each client individually
        rate-limit-client = {
          type = "rate-limiter";
          resolvers = [ "blocklist-request" ];
          limit-resolver = "static-refused";
          # Max 100 requests per host-IP per 2 minutes
          requests = 100;
          window = 120;
          prefix4 = 32;
          prefix6 = 128;
        };

        # Block queries (by domain name) using lists loaded from remote locations with HTTP and refreshed once a day
        blocklist-request = {
          type = "blocklist-v2";
          resolvers = [ "blocklist-response" ];
          blocklist-refresh = 86400; # 24 hours
          blocklist-source = [
            # WARN; MUST PICK DOT-version if available!
            # DOC; (Type) Domain - A list of domains with some wildcard capabilities. Also results in an NXDOMAIN. Entries in the list are matched as follows:
            #  - domain.com matches just domain.com and no sub-domains.
            #  - .domain.com matches domain.com and all sub-domains.
            #  - *.domain.com matches all subdomains but not domain.com. Only one wildcard (at the start of the string) is allowed.
            #
            # SEEALSO; cbuijs' lists
            ({
              name = "recent-domains-shreshtait";
              cache-dir = "/var/cache/routedns";
              allow-failure = false;
              format = "domain";
              source = "https://shreshtait.com/newly-registered-domains/nrd-1m";
            })
            ({
              name = "recent-domains-cbuijs";
              cache-dir = "/var/cache/routedns";
              allow-failure = false;
              format = "domain";
              source = "https://raw.githubusercontent.com/cbuijs/accomplist/refs/heads/main/chris/nrd-30-days-dot.list";
            })
            ({
              name = "abuse-tlds-cbuijs";
              cache-dir = "/var/cache/routedns";
              allow-failure = false;
              format = "domain";
              source = "https://raw.githubusercontent.com/cbuijs/accomplist/refs/heads/main/chris/abuse-tld-registered-dot.list";
            })
            ({
              name = "malware-fakenews-steven-black";
              cache-dir = "/var/cache/routedns";
              allow-failure = false;
              format = "hosts";
              source = "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts";
            })
            ({
              name = "adblock-privacy-hagezi";
              cache-dir = "/var/cache/routedns";
              allow-failure = false;
              format = "domain";
              source = "https://gitlab.com/hagezi/mirror/-/raw/main/dns-blocklists/domains/pro.txt";
            })
            ({
              name = "malware-hagezi";
              cache-dir = "/var/cache/routedns";
              allow-failure = false;
              format = "domain";
              source = "https://gitlab.com/hagezi/mirror/-/raw/main/dns-blocklists/domains/tif.txt";
            })
          ];
        };
        # Block queries that cloak, aka block based on domain names in CNAME, MX, NS, PRT and SRV records
        blocklist-response = {
          type = "response-blocklist-name";
          resolvers = [ "blocklist-ip" ];
          blocklist-refresh = 86400; # 24 hours
          blocklist-source = [
            ({
              name = "cloaked-domains-cbuijs";
              cache-dir = "/var/cache/routedns";
              allow-failure = false;
              format = "domain";
              # ERROR; Should be dotted!
              source = "https://raw.githubusercontent.com/cbuijs/accomplist/refs/heads/main/chris/cloak.list";
            })
          ];
        };

        # Block queries resolving to malicious IPs
        # WARN; IP address blocking results in a high false-positive rate!
        blocklist-ip = {
          type = "response-blocklist-ip";
          resolvers = [ "rate-limit-upstream" ];
          blocklist-refresh = 86400; # 24 hours
          blocklist-source = [ ];
        };

        # Put a limit to the amount of upstream requests
        rate-limit-upstream = {
          type = "rate-limiter";
          resolvers = [ "cloudflare" ];
          limit-resolver = "static-refused";
          # Max 200 requests per client subnet per minute
          requests = 100;
          window = 60;
          prefix4 = 24;
          prefix6 = 64;
        };

        # Route requests here to reply with REFUSED
        static-refused = {
          type = "static-responder";
          # NOTE; We want explicit refused so it's not cached upstream and retried by the client later.
          # NOTE; NXDOMAIN <=> code 3
          rcode = 5; # REFUSED
        };

        # Resolver group that uses 2 cloudflare upstream resolvers, additional ones can be added
        cloudflare = {
          type = "fail-rotate";
          resolvers = [
            "cloudflare-dot-1"
            "cloudflare-dot-2"
          ];
        };
      };

      resolvers = {
        # Cloudflare DNS-over-TLS, blocking websites with malware.
        # NOTE; Performance regarding "blocking websites with unwanted software" is absymall (RIP dns0).
        #
        # WARN; ISPs started to intercept, and inject into, plain-DNS queries to block websites provided legal pressure.
        # Must use one of the encrypted-DNS variants to prevent ISP hijacking!
        cloudflare-dot-1 = {
          address = "security.cloudflare-dns.com:853";
          bootstrap-address = "1.1.1.2";
          protocol = "dot";
        };
        cloudflare-dot-2 = {
          address = "security.cloudflare-dns.com:853";
          bootstrap-address = "1.0.0.2";
          protocol = "dot";
        };
      };
    };
  };

  systemd.services.routedns = {
    serviceConfig = {
      # Store blocklists, the path /var/cache/routedns is referenced inside the config.
      CacheDirectory = "routedns";

      # NOTE; Upstream has the unit configured to automatically restart on error!
    };
  };

  networking.firewall = {
    allowedUDPPorts = [ 53 ];
    allowedTCPPorts = [ 53 ];
  };
}
