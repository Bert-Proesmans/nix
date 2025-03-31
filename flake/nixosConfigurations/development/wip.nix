{ lib, flake, pkgs, config, ... }:
{
  sops.secrets.crowdsec-apikey.owner = "crowdsec";

  imports = [ flake.inputs.crowdsec.nixosModules.crowdsec ];
  services.crowdsec = {
    enable = true;
    enrollKeyFile = config.sops.secrets.crowdsec-apikey.path;
    allowLocalJournalAccess = true;

    acquisitions = [{
      source = "journalctl";
      journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
      labels.type = "syslog";
    }];

    settings =
      let
        # NOTE; Derived from upstream module config
        configDir = "/var/lib/crowdsec/config";
      in
      {
        api.server.listen_uri = "127.0.0.1:8080";
        prometheus.enabled = false;
        config_paths = {
          # Setup a R/W path to dynamically enable/disable simulations.
          # SEEALSO; systemd.services.crowdsec.serviceConfig.ExecStartPre
          simulation_path = "${configDir}/simulation.yaml";
        };

      };
  };

  systemd.services.crowdsec.serviceConfig = {
    ExecStartPre =
      let
        installConfigurations = pkgs.writeShellApplication {
          name = "install-configurations";
          # ERROR; crowdsec cli tool is wrapped with setting arguments, we need those!
          runtimeInputs = config.systemd.services.crowdsec.path;
          text = ''
            # WARN; Required on first run to hydrate the hub index
            # Is executed by the upstream ExecStartPre script!
            # cscli hub upgrade

            ## Collections
            cscli collections install \
              crowdsecurity/linux

            ## Parsers
            # Whitelists private IPs
            # if ! cscli parsers list | grep -q "whitelists"; then
            #     cscli parsers install crowdsecurity/whitelists
            # fi

            ## Heavy operations
            cscli postoverflows install \
              crowdsecurity/ipv6_to_range \
              crowdsecurity/rdns

            ## Non-actionable scenario's
            echo 'simulation: false' >'${config.services.crowdsec.settings.config_paths.simulation_path}'
            cscli simulation enable crowdsecurity/http-bad-user-agent
            cscli simulation enable crowdsecurity/http-crawl-non_statics
            cscli simulation enable crowdsecurity/http-probing
          '';
        };
      in
      lib.mkAfter [ (lib.getExe installConfigurations) ];
    ExecStartPost =
      let
        waitForStart = pkgs.writeShellApplication {
          name = "wait-for-start";
          # ERROR; crowdsec cli tool is wrapped with setting arguments, we need those!
          runtimeInputs = config.systemd.services.crowdsec.path ++ [ pkgs.coreutils ];
          text = ''
            while ! nice -n19 cscli lapi status; do
              echo "Waiting for CrowdSec daemon to be ready"
              sleep 10
            done
          '';
        };
      in
      lib.mkBefore [ (lib.getExe waitForStart) ];
  };
}
