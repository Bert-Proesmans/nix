{
  lib,
  config,
  ...
}:
let
  # NOTE; sudo -u crowdsec cscli lapi register --url 'http://buddy.tailaac73.ts.net'
  controller-url-crowdsec = lib.pipe config.proesmans.facts.buddy.services [
    # Want the service endpoint over tailscale
    (lib.filterAttrs (_ip: v: builtins.elem "tailscale" v.tags))
    (lib.mapAttrsToList (ip: _: "http://${ip}:10124"))
    (lib.flip builtins.elemAt 0)
  ];
in
{
  sops.secrets."01-fart-sensor-crowdsec-key".owner = "crowdsec";
  # WARN; Bouncer service is running as root !
  sops.secrets."01-fart-bouncer-crowdsec-key".owner = "root";

  services.crowdsec = {
    # NOTE; Setup as remote sensor
    enable = true;

    allowLocalJournalAccess = true;
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

    settings = {
      # This instance acts as a sensor for another controller engine!
      api.server.enable = false;
      prometheus.enabled = false;
      cscli.output = "human";
    };

    # Attach this crowdsec engine to the central LAPI on host buddy
    lapiConnect.url = controller-url-crowdsec;
    lapiConnect.name = "01-fart";
    lapiConnect.passwordFile = config.sops.secrets."01-fart-sensor-crowdsec-key".path;

    extraSetupCommands = ''
      ## Collections
      cscli collections install \
        crowdsecurity/linux \
        crowdsecurity/haproxy        

      ## Heavy operations
      cscli postoverflows install \
        crowdsecurity/ipv6_to_range \
        crowdsecurity/rdns
    '';
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
