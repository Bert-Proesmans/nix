{ ... }: {
  # Disable resolved (systemd) to free up the DNS port on loopback.
  services.resolved.enable = false;
  services.routedns.enable = true;
  services.routedns.configFile = ./routedns-config.toml;
  # Create a directory where blocklists are cached. Within service configuration
  # reference the full path; /var/cache/routedns.
  systemd.services.routedns = {
    # Dns service downloads block lists from internet at start
    #
    # WARN; The service will still write out a warning about the blocklist files not existing inside the cache
    # directory, which is expected because that's not persisted.
    # That same warning will look very vaguely about download failure, but isn't about the download!
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    # Store blocklists
    serviceConfig.CacheDirectory = "routedns";
  };
  networking.firewall = {
    allowedUDPPorts = [ 53 ];
    allowedTCPPorts = [ 53 ];
  };
}
