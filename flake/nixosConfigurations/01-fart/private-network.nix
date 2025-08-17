{
  config,
  ...
}:
{
  sops.secrets.tailscale_connect_key.owner = "root";
  services.tailscale = {
    enable = true;
    disableTaildrop = true;
    openFirewall = true;
    useRoutingFeatures = "none";
    authKeyFile = config.sops.secrets.tailscale_connect_key.path;
    extraDaemonFlags = [ "--no-logs-no-support" ];
  };
}
