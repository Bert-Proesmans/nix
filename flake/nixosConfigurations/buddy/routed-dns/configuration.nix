{ ... }:
{
  # Disable resolved (systemd) to free up the DNS port on loopback.
  services.resolved.enable = false;
  services.routedns.enable = true;

  # WARN; The service will throw warnings about blocklists not being cached. These warnings will suspiciously look
  # like errors. It just means that routedns will download the requested files.
  # NOTE; The configuration is setup to fail the service if the blocklists cannot be downloaded!
  services.routedns.configFile = ./routedns-config.toml;

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
