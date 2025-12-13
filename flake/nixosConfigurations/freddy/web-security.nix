{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (config.proesmans.facts.self.service) crowdsec-lapi;

  # Hardcoded upstream
  rootDir = "/var/lib/crowdsec";
  stateDir = "${rootDir}/state";
in
{
  users.groups."local-crowdsec" = { };

  sops.secrets.crowdsec-apikey.owner = "crowdsec";
  sops.secrets."local-bouncer-crowdsec-key" = {
    mode = "0440";
    owner = "crowdsec";
    # NOTE; The firewall bouncer does _not_ run as user crowdsec!
    group = config.users.groups."local-crowdsec".name;
  };
  sops.secrets."01-fart-sensor-crowdsec-key".owner = "crowdsec";
  sops.secrets."01-fart-bouncer-crowdsec-key".owner = "crowdsec";
  sops.secrets."02-fart-sensor-crowdsec-key".owner = "crowdsec";
  sops.secrets."02-fart-bouncer-crowdsec-key".owner = "crowdsec";

  services.crowdsec = {
    enable = true;
    autoUpdateService = true;
    openFirewall = false;

    localConfig = {
      # NOTE; For journalctl watching, use argument '-o' to get all log metadata properties that can be used for filtering
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
          journalctl_filter = [ "_SYSTEMD_UNIT=nginx.service" ];
          labels.type = "nginx";
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
        "crowdsecurity/nginx"
      ];
      scenarios = [ ];
      parsers = [ ];
      postOverflows = [
        "crowdsecurity/ipv6_to_range"
        "crowdsecurity/rdns"
      ];
      # appSecConfigs = [ ];
      # appSecRules = [ ];
    };

    settings = {
      general = {
        api.server.enable = true;
        api.server.listen_uri = "0.0.0.0:${toString crowdsec-lapi.port}";
        # ERROR; Must set path to R/W location to dynamically update console properties at registration
        api.server.console_path = (lib.strings.normalizePath "${stateDir}/console.yaml");
        prometheus.enabled = false;
        cscli.output = "human";
      };
      # simulation = { };
      # _local_ API => Single or distributed setup
      lapi = {
        # ERROR; Must use stateDir because rootDir is not owned by service user (crowdsec)
        credentialsFile = (lib.strings.normalizePath "${stateDir}/local_api_credentials.yaml");
      };
      # _community_ API => Share blocklists and alerts
      capi = {
        # ERROR; Must set path to R/W location to persist CAPI login credentials
        # WORKAROUND; Activate flow for CAPI / Console registration
        credentialsFile = (lib.strings.normalizePath "${stateDir}/online_api_credentials.yaml");
      };
      # Crowdsec SAAS product to dashboard your engine data
      console.tokenFile = config.sops.secrets."crowdsec-apikey".path;
    };

    sensors = {
      "01-fart".passwordFile = config.sops.secrets."01-fart-sensor-crowdsec-key".path;
      "02-fart".passwordFile = config.sops.secrets."02-fart-sensor-crowdsec-key".path;
    };
    bouncers = {
      "${config.networking.hostName}".passwordFile =
        config.sops.secrets."local-bouncer-crowdsec-key".path;
      "01-fart".passwordFile = config.sops.secrets."01-fart-bouncer-crowdsec-key".path;
      "02-fart".passwordFile = config.sops.secrets."02-fart-bouncer-crowdsec-key".path;
    };
  };

  systemd.services.crowdsec = {
    # WORKAROUND; Properly enroll into console
    serviceConfig.ExecStartPre = lib.mkAfter [
      (
        let
          cfg = config.services.crowdsec;
          demoScript = pkgs.writeShellApplication {
            name = "crowdsec-debug";
            runtimeInputs = [
              pkgs.gnugrep
              cfg.cscliPackage
              pkgs.coreutils
            ];
            text = ''
              # NOTE; CAPI register should happen upstream
              if ! grep -q password "${cfg.settings.general.api.server.online_client.credentials_path}"; then
                cscli capi register
              fi

              if grep -q password "${cfg.settings.general.api.server.online_client.credentials_path}"; then
                # PREREQUISITE; Local API is enrolled into the central API (CAPI)
                if [ -s "${cfg.settings.console.tokenFile}" ]; then
                  # Tokenfile exists and is non-empty
                  cscli console enroll "$(cat ${cfg.settings.console.tokenFile})" --name ${config.networking.hostName}
                fi
              fi
            '';
          };
        in
        lib.getExe demoScript
      )
    ];
  };

  systemd.tmpfiles.rules =
    let
      cfg = config.services.crowdsec;
    in
    [
      # WORKAROUND; cscli refuses to work if file does not exist at path
      "f '${cfg.settings.general.api.server.online_client.credentials_path}' 0750 ${cfg.user} ${cfg.group} - -"
    ];

  services.crowdsec-firewall-bouncer = {
    enable = true;
    # NOTE; ROOT ownership is OK due to SystemD LoadCredential.
    secrets.apiKeyPath = config.sops.secrets."local-bouncer-crowdsec-key".path;
    settings = {
      api_url = crowdsec-lapi.uri "127.0.0.1";
      log_mode = "stdout";
      update_frequency = "10s";
    };
  };

  systemd.services.crowdsec-firewall-bouncer = {
    # NOTE; The bouncer runs as root!
    # ERROR; Must provide read access to the secret value because secret owner _is not_ root.
    serviceConfig.SupplementaryGroups = config.users.groups."local-crowdsec".name;
  };
}
