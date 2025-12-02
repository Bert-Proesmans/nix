{
  lib,
  utils,
  flake,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.crowdsec-firewall-bouncer;
in
{
  options.services.crowdsec-firewall-bouncer = { };

  config = lib.mkIf (cfg.enable) ({
    services.crowdsec-firewall-bouncer = {
      createRulesets = lib.mkDefault true;
      # Only works automatically if the LAPI is running on this host (localhost)
      registerBouncer.enable = lib.mkDefault false;
      registerBouncer.bouncerName = config.networking.hostname;
    };

    systemd.targets.crowdsec = {
      description = lib.mkDefault "Crowdsec";
      wantedBy = [ "multi-user.target" ];
      requires = [ config.systemd.services.crowdsec-firewall-bouncer.name ];
    };

    systemd.services = {
      crowdsec-firewall-bouncer-register = lib.mkIf cfg.registerBouncer.enable {
        wants = [
          config.systemd.services.crowdsec.name
          config.systemd.services.crowdsec-lapi-setup.name
        ];

        after = [
          config.systemd.services.crowdsec.name
          config.systemd.services.crowdsec-lapi-setup.name
        ];
      };

      crowdsec-firewall-bouncer = {
        partOf = [ config.systemd.targets.crowdsec.name ];
      };
    };
  });
}
