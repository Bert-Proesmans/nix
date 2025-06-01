{ lib, flake, pkgs, config, ... }:
let
  # TODO; Check connection to upstream controller engine (Local API [LAPI])
  # WARN; Hardcoded upstream
  state-dir-crowdsec = "/var/lib/crowdsec";
  config-dir-crowdsec = "${state-dir-crowdsec}/config";

  # NOTE; sudo -u crowdsec cscli lapi register --url 'http://buddy.tailaac73.ts.net'
  controller-crowdsec = "buddy.tailaac73.ts.net";
in
{
  imports = [
    flake.inputs.crowdsec.nixosModules.crowdsec
  ];

  services.crowdsec = {
    enable = true;

    allowLocalJournalAccess = true;
    acquisitions = [
      ({
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
        labels.type = "syslog";
      })
      # ({
      #   source = "journalctl";
      #   journalctl_filter = [ "_SYSTEMD_UNIT=nginx.service" ];
      #   labels.type = "syslog";
      # })
    ];

    settings = {
      # This instance acts as a sensor for another controller engine!
      api.server.enable = false;
      prometheus.enabled = false;
      cscli.output = "human";
      config_paths = {
        # Setup a R/W path to dynamically enable/disable simulations.
        # SEEALSO; systemd.services.crowdsec.serviceConfig.ExecStartPre
        # simulation_path = "${config-dir-crowdsec}/simulation.yaml";
      };
    };
  };

  sops.secrets."01-fart-sensor-crowdsec-key".owner = "crowdsec";
  # sops.secrets."01-fart-bouncer-crowdsec-key".owner = "crowdsec";
  systemd.services.crowdsec.serviceConfig = {
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

        register = pkgs.writeShellApplication {
          name = "register-sensor";
          # ERROR; crowdsec cli tool is wrapped with setting arguments, we need those!
          runtimeInputs = config.systemd.services.crowdsec.path ++ [ pkgs.coreutils ];
          text = ''
            # 01-fart sensor
            if ! cscli lapi status; then
              PASS="''$(cat '${config.sops.secrets."01-fart-sensor-crowdsec-key".path}')"
              # NOTE; Command will create /var/lib/crowdsec/local_api_credentials.yaml
              # TODO; Not hardcode controller URL
              cscli lapi register --token "''$PASS" --url 'http://buddy.tailaac73.ts.net:10124'
            fi
          '';
        };
      in
      lib.mkMerge [
        (lib.mkBefore [ (lib.getExe register) (lib.getExe waitForStart) ])
        (lib.mkAfter [ ])
      ];
  };
}
