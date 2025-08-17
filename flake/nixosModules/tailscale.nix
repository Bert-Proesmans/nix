{ lib, config, ... }:
let
  cfg = config.services.tailscale;
in
{
  # WIP - Is this really necessary?
  config = lib.mkIf (cfg.enable && false) {
    systemd.targets = {
      "tailscale-online" = {
        after = [ config.systemd.services.tailscaled.name ];
        bindsTo = [ config.systemd.services.tailscaled.name ];
      };
      "tailscale-offline" = {
        after = [ config.systemd.services.tailscaled.name ];
        conflicts = [ ];
      };
    };

    systemd.services."tailscale-poller" = {
      description = "Test Tailscale VPN connection";
      startAt = "*-*-* 00:00:00/5"; # Every 5 seconds
      after = [ config.systemd.services.tailscaled.name ];
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = "no";
      enableStrictShellChecks = true;
      script = ''
        timeout 60s bash -c 'until tailscale status --peers=false; do sleep 1; done'
      '';
    };
  };
}
