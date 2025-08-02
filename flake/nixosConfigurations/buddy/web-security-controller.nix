{
  lib,
  flake,
  pkgs,
  config,
  ...
}:
let
  api-url-crowdsec = "0.0.0.0:10124";
  # WARN; Hardcoded upstream
  state-dir-crowdsec = "/var/lib/crowdsec";
  config-dir-crowdsec = "${state-dir-crowdsec}/config";
in
{
  imports = [
    flake.inputs.crowdsec.nixosModules.crowdsec
  ];

  sops.secrets.crowdsec-apikey.owner = "crowdsec";
  services.crowdsec = {
    enable = true;
    enrollKeyFile = config.sops.secrets.crowdsec-apikey.path;

    allowLocalJournalAccess = true;
    acquisitions = [
      ({
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
        labels.type = "syslog";
      })
      ({
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=nginx.service" ];
        labels.type = "syslog";
      })
    ];

    settings = {
      api.server.listen_uri = api-url-crowdsec;
      prometheus.enabled = false;
      cscli.output = "human";
      config_paths = {
        # Setup a R/W path to dynamically enable/disable simulations.
        # SEEALSO; systemd.services.crowdsec.serviceConfig.ExecStartPre
        simulation_path = "${config-dir-crowdsec}/simulation.yaml";
      };
    };
  };

  sops.secrets."01-fart-sensor-crowdsec-key".owner = "crowdsec";
  sops.secrets."01-fart-bouncer-crowdsec-key".owner = "crowdsec";
  sops.secrets."02-fart-sensor-crowdsec-key".owner = "crowdsec";
  sops.secrets."02-fart-bouncer-crowdsec-key".owner = "crowdsec";
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
            # cscli hub update

            ## Collections
            cscli collections install \
              crowdsecurity/linux \
              crowdsecurity/nginx

            ## Parsers
            # Whitelists private IPs
            # if ! cscli parsers list | grep -q "whitelists"; then
            #     cscli parsers install crowdsecurity/whitelists
            # fi

            ## Heavy operations
            cscli postoverflows install \
              crowdsecurity/ipv6_to_range \
              crowdsecurity/rdns

            ## Report-only (no action taken) scenario's
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

        sensors = pkgs.writeShellApplication {
          name = "setup-sensors";
          # ERROR; crowdsec cli tool is wrapped with setting arguments, we need those!
          runtimeInputs = config.systemd.services.crowdsec.path ++ [ pkgs.coreutils ];
          text = ''
            # 01-fart sensor
            if ! cscli machines list | grep -q '01-fart'; then
              PASS="''$(cat '${config.sops.secrets."01-fart-sensor-crowdsec-key".path}')"
              cscli machines add '01-fart' --password "''$PASS" -f- > /dev/null
            fi

            # 02-fart sensor
            if ! cscli machines list | grep -q '02-fart'; then
              PASS="''$(cat '${config.sops.secrets."02-fart-sensor-crowdsec-key".path}')"
              cscli machines add '02-fart' --password "''$PASS" -f- > /dev/null
            fi
          '';
        };

        bouncers = pkgs.writeShellApplication {
          name = "setup-bouncers";
          # ERROR; crowdsec cli tool is wrapped with setting arguments, we need those!
          runtimeInputs = config.systemd.services.crowdsec.path ++ [ pkgs.coreutils ];
          text = ''
            # 01-fart bouncer
            if ! cscli bouncers list | grep -q '01-fart'; then
              PASS="''$(cat '${config.sops.secrets."01-fart-bouncer-crowdsec-key".path}')"
              cscli bouncers add '01-fart' --key "''$PASS"
            fi

            # 02-fart bouncer
            if ! cscli bouncers list | grep -q '02-fart'; then
              PASS="''$(cat '${config.sops.secrets."02-fart-bouncer-crowdsec-key".path}')"
              cscli bouncers add '02-fart' --key "''$PASS"
            fi
          '';
        };
      in
      lib.mkMerge [
        (lib.mkBefore [ (lib.getExe waitForStart) ])
        (lib.mkAfter [
          (lib.getExe sensors)
          (lib.getExe bouncers)
        ])
      ];
  };
}
