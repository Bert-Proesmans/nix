{ ... }: {
  # Disable resolved (systemd) to free up the DNS port on loopback.
  services.resolved.enable = false;
  services.routedns.enable = true;
  services.routedns.configFile = ./routedns-config.toml;
  # Create a directory where blocklists are cached. Within service configuration
  # reference the full path; /var/cache/routedns.
  systemd.services.routedns.serviceConfig.CacheDirectory = "routedns";
  networking.firewall = {
    allowedUDPPorts = [ 53 ];
    allowedTCPPorts = [ 53 ];
  };
}
