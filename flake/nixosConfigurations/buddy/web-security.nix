{
  lib,
  pkgs,
  config,
  ...
}:
{
  sops.secrets.crowdsec-apikey.owner = "crowdsec";
  sops.secrets."01-fart-sensor-crowdsec-key".owner = "crowdsec";
  sops.secrets."01-fart-bouncer-crowdsec-key".owner = "crowdsec";
  # sops.secrets."02-fart-sensor-crowdsec-key".owner = "crowdsec";
  # sops.secrets."02-fart-bouncer-crowdsec-key".owner = "crowdsec";
  services.crowdsec = {
    enable = true;
    enrollKeyFile = config.sops.secrets.crowdsec-apikey.path;

    allowLocalJournalAccess = true;
    # NOTE; For journalctl watching, use argument '-o' to get all log metadata properties that can be used for filtering
    acquisitions = [
      ({
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=haproxy.service" ];
        labels.type = "haproxy";
      })
      ({
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=immich-server.service" ];
        labels.type = "immich";
      })
    ];

    settings = {
      # NOTE; Listen on all interfaces because the API must be accessible over Tailscale VPN too!
      api.server.listen_uri = "0.0.0.0:10124";
      prometheus.enabled = false;
      cscli.output = "human";
    };

    sensors = {
      "01-fart".passwordFile = config.sops.secrets."01-fart-sensor-crowdsec-key".path;
      # "02-fart".passwordFile = config.sops.secrets."02-fart-sensor-crowdsec-key".path;
    };
    bouncers = {
      "01-fart".passwordFile = config.sops.secrets."01-fart-bouncer-crowdsec-key".path;
      # "02-fart".passwordFile = config.sops.secrets."02-fart-bouncer-crowdsec-key".path;
    };

    extraSetupCommands = ''
      ## Collections
      cscli collections install \
        crowdsecurity/linux \
        crowdsecurity/haproxy \
        gauth-fr/immich

      ## Heavy operations
      cscli postoverflows install \
        crowdsecurity/ipv6_to_range \
        crowdsecurity/rdns
    '';
  };
}
