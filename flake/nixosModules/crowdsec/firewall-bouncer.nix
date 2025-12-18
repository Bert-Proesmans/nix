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

        serviceConfig = rec {
          TimeoutSec = 90;
          Restart = "always";
          RestartSec = 60;

          # Bouncer is effectively not working. Workaround can be removed when PR below is merged.
          # REF; https://github.com/NixOS/nixpkgs/pull/459188
          AmbientCapabilities = lib.optional (
            (cfg.settings.mode == "iptables") || (cfg.settings.mode == "ipset")
          ) "CAP_NET_RAW";
          CapabilityBoundingSet = AmbientCapabilities;
        };
        unitConfig =
          let
            inherit (config.systemd.services.crowdsec-firewall-bouncer.serviceConfig) TimeoutSec;
            maxTries = 5;
            bufferSec = 5;
          in
          {
            # The max. time needed to perform `maxTries` start attempts of systemd
            # plus a bit of buffer time (bufferSec) on top.
            StartLimitIntervalSec = TimeoutSec * maxTries + bufferSec;
            StartLimitBurst = maxTries;
          };
      };
    };
  });
}
