{
  lib,
  config,
  ...
}:
let
  # Hardcoded upstream
  rootDir = "/var/lib/crowdsec";
  stateDir = "${rootDir}/state";
in
{
  sops.secrets.crowdsec-apikey.owner = "crowdsec";
  sops.secrets."01-fart-sensor-crowdsec-key".owner = "crowdsec";
  sops.secrets."01-fart-bouncer-crowdsec-key".owner = "crowdsec";
  # sops.secrets."02-fart-sensor-crowdsec-key".owner = "crowdsec";
  # sops.secrets."02-fart-bouncer-crowdsec-key".owner = "crowdsec";
  services.crowdsec = {
    enable = true;
    autoUpdateService = true;
    openFirewall = false;

    localConfig = {
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
        ({
          source = "journalctl";
          journalctl_filter = [ "_SYSTEMD_UNIT=vaultwarden.service" ];
          labels.type = "Vaultwarden";
        })
      ];

      # patterns = [ ];
      parsers = {
        s00Raw = [ ];
        s01Parse = import ./crowdsec/s01-parsers.nix;
        s02Enrich = [ ];
      };
      # postOverflows = { };
      # scenarios = { };
      # contexts = [ ];
      # notifications = [ ];
      # profiles = [ ];
    };

    hub = {
      collections = [
        "crowdsecurity/linux"
        "crowdsecurity/haproxy"
        "gauth-fr/immich"
        "Dominic-Wagner/vaultwarden"
      ];
      scenarios = [ ];
      parsers = [ ];
      postOverflows = [
        "crowdsecurity/ipv6_to_range"
        "crowdsecurity/rdns"
      ];
      # appSecConfigs = [ ];
      # appSecRules = [ ];
    };

    settings = {
      general = {
        api.server.enable = true;
        api.server.listen_uri = "0.0.0.0:10124";
        prometheus.enabled = false;
        cscli.output = "human";
      };
      # simulation = { };
      # _local_ API => Single or distributed setup
      lapi = {
        # ERROR; Must use stateDir because rootDir is not owned by service user (crowdsec)
        credentialsFile = (lib.strings.normalizePath "${stateDir}/local_api_credentials.yaml");
      };
      # _community_ API => Share blocklists and alerts
      capi = { };
      # Crowdsec SAAS product to dashboard your engine data
      console.tokenFile = config.sops.secrets.crowdsec-apikey.path;
    };

    sensors = {
      "01-fart".passwordFile = config.sops.secrets."01-fart-sensor-crowdsec-key".path;
      # "02-fart".passwordFile = config.sops.secrets."02-fart-sensor-crowdsec-key".path;
    };
    bouncers = {
      "01-fart".passwordFile = config.sops.secrets."01-fart-bouncer-crowdsec-key".path;
      # "02-fart".passwordFile = config.sops.secrets."02-fart-bouncer-crowdsec-key".path;
    };
  };
}
