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
          address = "0.0.0.0:53";
          protocol = "udp";
          resolver = "cache";
        };
        network-tcp = {
          address = "0.0.0.0:53";
          protocol = "tcp";
          resolver = "cache";
        };
      };

      groups = {
        cache = {
          type = "cache";
          resolvers = [ "ttl-update" ];
          cache-negative-ttl = 60; # 1 minute
          backend.type = "memory";
          backend.size = 8192; # units
        };

        ttl-update = {
          # Update TTL to avoid noise using values that are too low
          type = "ttl-modifier";
          resolvers = [ "rate-limit-client" ];
          ttl-min = 1800; # 30 Minutes
          ttl-max = 43200; # 12 Hours
        };

        rate-limit-client = {
          # Rate limit requests for each client
          type = "rate-limiter";
          resolvers = [ "blocklist" ];
          limit-resolver = "static-refused";
          # Max 100 requests per host-IP per 2 minutes
          requests = 100;
          window = 120;
          prefix4 = 32;
          prefix6 = 128;
        };

        # Block queries (by name) using lists loaded from remote locations with HTTP and refreshed once a day
        blocklist = {
          type = "blocklist-v2";
          resolvers = [ "blocklist-response" ];
          blocklist-refresh = 86400; # 24 hours
          blocklist-source = [
            ({
              name = "recent-domains";
              cache-dir = "/var/cache/routedns";
              allow-failure = false;
              format = "domain";
              source = "https://shreshtait.com/newly-registered-domains/nrd-1m";
            })
            ({
              name = "steven-black-malware-fakenews-blocklist";
              cache-dir = "/var/cache/routedns";
              allow-failure = false;
              format = "hosts";
              source = "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts";
            })
            # ({
            #   # REF; https://github.com/serverless-dns/blocklists/commit/f88589abb5b52a39a4c46ee00680c62c8769ba7f#commitcomment-107591979
            #   name = "cbuijs-abused-tlds";
            #   cache-dir = "/var/cache/routedns";
            #   allow-failure = false;
            #   format = "domain";
            #   # ERROR; 404 response due to Github intervention, repo is being rebuilt
            #   source = "https://raw.githubusercontent.com/cbuijs/accomplist/master/tlds/plain.black.domain.list";
            # })
            ({
              # REF; https://github.com/serverless-dns/blocklists/commit/f88589abb5b52a39a4c46ee00680c62c8769ba7f#commitcomment-107591979
              name = "cbuijs-easylist-adblock";
              cache-dir = "/var/cache/routedns";
              allow-failure = false;
              format = "domain";
              source = "https://raw.githubusercontent.com/cbuijs/accomplist/master/easylist/plain.black.domain.list";
            })
          ];
        };
        blocklist-response = {
          # Block responses that include blacklisted keywords
          type = "response-blocklist-name";
          resolvers = [ "blocklist-ip" ];
          blocklist-refresh = 86400; # 24 hours
          blocklist-source = [
            # ({
            #   name = "cbuijs-dynamic-content-malicious";
            #   cache-dir = "/var/cache/routedns";
            #   allow-failure = false;
            #   format = "domain";
            #   # ERROR; 404 response due to Github intervention, repo is being rebuilt
            #   source = "https://raw.githubusercontent.com/cbuijs/accomplist/master/cloak/plain.black.domain.list";
            # })
          ];
        };

        blocklist-ip = {
          # Block responses by IP ranges
          type = "response-blocklist-ip";
          resolvers = [ "rate-limit-upstream" ];
          blocklist-refresh = 86400; # 24 hours
          blocklist-source = [
            ({
              name = "cbuijs-bogon-ips";
              cache-dir = "/var/cache/routedns";
              allow-failure = false;
              format = "cidr";
              source = "https://raw.githubusercontent.com/cbuijs/accomplist/master/bogons/plain.black.ip4cidr.list";
            })
            # ({
            #   name = "cbuijs-malware-ips";
            #   cache-dir = "/var/cache/routedns";
            #   allow-failure = false;
            #   format = "cidr";
            #   # ERROR; This list of IPs blocks the cache.nixos.org website! This blocks nixos-rebuild from using the main file caches!
            #   # LOG; level=debug msg="blocking response" client=127.0.0.1 id=blocklist-ip ip=151.101.194.217 list=cbuijs-malware-ips
            #   #      qname=cache.nixos.org. qtype=A rule=151.101.194.217/32
            #   # TODO; Build out my own nixpkg cache!
            #   source = "https://raw.githubusercontent.com/cbuijs/accomplist/master/malicious-ip/plain.black.ipcidr.list";
            # })
          ];
        };

        rate-limit-upstream = {
          # Put a limit to the amount of upstream requests
          type = "rate-limiter";
          resolvers = [ "cloudflare" ];
          limit-resolver = "static-refused";
          # Max 200 requests per client subnet per minute
          requests = 100;
          window = 60;
          prefix4 = 24;
          prefix6 = 64;
        };

        static-refused = {
          # Route requests into this handler to terminate the response flow
          type = "static-responder";
          rcode = 5; # REFUSED
        };

        cloudflare = {
          # Resolver group that uses 2 cloudflare upstream resolvers, additional ones can be added
          type = "fail-rotate";
          resolvers = [
            "cloudflare-dot-1"
            "cloudflare-dot-2"
          ];
        };
      };

      resolvers = {
        # Cloudflare DNS-over-TLS, blocking websites with malware.
        # NOTE; Performance regarding "blocking websites with unwanted software" is absymall, prefer dns0 instead.
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
