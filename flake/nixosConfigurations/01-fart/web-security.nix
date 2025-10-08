{
  lib,
  config,
  ...
}:
let
  # NOTE; sudo -u crowdsec cscli lapi register --url 'http://buddy.tailaac73.ts.net'
  controller-url-crowdsec = lib.pipe config.proesmans.facts.freddy.services [
    # Want the service endpoint over tailscale
    (lib.filterAttrs (_ip: v: builtins.elem "tailscale" v.tags))
    (lib.mapAttrsToList (ip: _: "http://${ip}:10124"))
    (lib.flip builtins.elemAt 0)
  ];
in
{
  sops.secrets."01-fart-sensor-crowdsec-key" = { };
  # WARN; Bouncer service is running as root!
  sops.secrets."01-fart-bouncer-crowdsec-key" = { };

  sops.templates."crowdsec-connect.yaml" = {
    owner = "crowdsec";
    restartUnits = [ config.systemd.services.crowdsec.name ];
    content = ''
      url: ${controller-url-crowdsec}
      login: ${"01-fart"}
      password: ${config.sops.placeholder."01-fart-sensor-crowdsec-key"}
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
      ];
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
    settings = {
      api_key = {
        _secret = config.sops.secrets."01-fart-bouncer-crowdsec-key".path;
      };
      api_url = controller-url-crowdsec;
      log_mode = "stdout";
      update_frequency = "10s";
    };
  };
}
