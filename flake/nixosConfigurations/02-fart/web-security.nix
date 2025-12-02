{
  lib,
  config,
  ...
}:
let
  freddy = config.proesmans.facts.freddy;
  # NOTE; sudo -u crowdsec cscli lapi register --url '<uri>'
  controller-url-crowdsec = freddy.service.crowdsec-lapi.uri freddy.host.tailscale.address;
in
{
  sops.secrets."02-fart-sensor-crowdsec-key" = { };
  # WARN; Bouncer service is running as root!
  sops.secrets."02-fart-bouncer-crowdsec-key" = { };

  sops.templates."crowdsec-connect.yaml" = {
    owner = "crowdsec";
    restartUnits = [ config.systemd.services.crowdsec.name ];
    content = ''
      url: ${controller-url-crowdsec}
      login: ${"02-fart"}
      password: ${config.sops.placeholder."02-fart-sensor-crowdsec-key"}
    '';
  };

  services.crowdsec = {
    # NOTE; Setup as remote sensor
    enable = true;
    autoUpdateService = true;
    openFirewall = false;

    localConfig = {
      acquisitions = [
        ({
          source = "journalctl";
          journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
          labels.type = "ssh";
        })
        ({
          source = "journalctl";
          journalctl_filter = [ "_SYSTEMD_UNIT=haproxy.service" ];
          labels.type = "haproxy";
        })
        ({
          source = "journalctl";
          journalctl_filter = [ "_SYSTEMD_UNIT=kanidm.service" ];
          labels.type = "kanidm";
        })
      ];

      # patterns = [ ];
      parsers = {
        s00Raw = [ ];
        # WARN; These parsers are added to a stateful directory! Changing the contents will add duplicates!
        # Regularly clean /etc/crowdsec/* when iterating.
        s01Parse = import ./crowdsec/s01-parsers.nix;
        s02Enrich = [ ];
      };
      # postOverflows = { };
      # WARN; These scenarios are added to a stateful directory! Changing the contents will add duplicates!
      # Regularly clean /etc/crowdsec/* when iterating.
      scenarios = import ./crowdsec/scenarios.nix;
      # contexts = [ ];
      # notifications = [ ];
      # profiles = [ ];
    };

    hub = {
      collections = [
        "crowdsecurity/linux"
        "crowdsecurity/haproxy"
      ];
      scenarios = [ ];
      parsers = [ ];
      postOverflows = [
        "crowdsecurity/ipv6_to_range"
        "crowdsecurity/rdns"
      ];
    };

    settings = {
      general = {
        # This instance acts as a sensor for another controller engine!
        api.server.enable = false;
        prometheus.enabled = false;
        cscli.output = "human";
      };
      lapi = {
        credentialsFile = config.sops.templates."crowdsec-connect.yaml".path;
      };
    };
  };

  services.crowdsec-firewall-bouncer = {
    # NOTE; Setup as remote bouncer
    enable = true;
    # NOTE; ROOT ownership is OK due to SystemD LoadCredential.
    secrets.apiKeyPath = config.sops.secrets."02-fart-bouncer-crowdsec-key".path;
    settings = {
      api_url = controller-url-crowdsec;
      log_mode = "stdout";
      update_frequency = "10s";
    };
  };
}
