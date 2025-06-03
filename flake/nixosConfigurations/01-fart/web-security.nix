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
        simulation_path = "${config-dir-crowdsec}/simulation.yaml";
      };
    };
  };

  sops.secrets."01-fart-sensor-crowdsec-key".owner = "crowdsec";
  # sops.secrets."01-fart-bouncer-crowdsec-key".owner = "crowdsec";
  systemd.services.crowdsec.serviceConfig = {
    ExecStartPre =
      let
        register = pkgs.writeShellApplication {
          name = "register-sensor";
          # ERROR; crowdsec cli tool is wrapped with setting arguments, we need those!
          runtimeInputs = config.systemd.services.crowdsec.path ++ [ pkgs.coreutils ];
          text = ''
            # 01-fart sensor
            if [ ! -s '${config.services.crowdsec.settings.api.client.credentials_path}' ]; then
              # ERROR; Cannot use 'cscli lapi register ..' because that command wants a valid local_api_credentials file, which we
              # want to created as new with that same command.. /facepalm
              LAPI_URL='http://buddy.tailaac73.ts.net:10124'
              HOSTNAME='01-fart'
              PASSWORD="''$(cat '${config.sops.secrets."01-fart-sensor-crowdsec-key".path}')"

              cat > '${config.services.crowdsec.settings.api.client.credentials_path}' <<EOF
            url: $LAPI_URL
            login: $HOSTNAME
            password: $PASSWORD
            EOF
            fi

            # WARN; Required to know about all published collections and other detection resources.
            # Is normally executed by the upstream ExecStartPre script!
            cscli hub update
          '';
        };

        installConfigurations = pkgs.writeShellApplication {
          name = "install-configurations";
          # ERROR; crowdsec cli tool is wrapped with setting arguments, we need those!
          runtimeInputs = config.systemd.services.crowdsec.path;
          text = ''
            ## Collections
            cscli collections install \
              crowdsecurity/linux              

            ## Parsers
            # Whitelists private IPs
            # if ! cscli parsers list | grep -q "whitelists"; then
            #     cscli parsers install crowdsecurity/whitelists
            # fi

            ## Heavy operations
            # cscli postoverflows install \
            #  crowdsecurity/ipv6_to_range
            #  crowdsecurity/rdns

            ## Report-only (no action taken) scenario's
            echo 'simulation: false' >'${config.services.crowdsec.settings.config_paths.simulation_path}'
            # cscli simulation enable crowdsecurity/http-bad-user-agent
            # cscli simulation enable crowdsecurity/http-crawl-non_statics
            # cscli simulation enable crowdsecurity/http-probing
          '';
        };
      in
      # WARN; Overwrite upstream pre-start script because that attempts to setup in standalone mode
      lib.mkForce [ (lib.getExe register) (lib.getExe installConfigurations) ];

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
