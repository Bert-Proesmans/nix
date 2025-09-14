{
  flake,
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.crowdsec;

  # ERROR; Upstream locked the cscli binary inside the module configuration.
  # Attempt to pick it out of the list of global system packages.
  cscli =
    let
      matches = builtins.filter (pkg: pkg.name == "cscli") config.environment.systemPackages;
    in
    assert !cfg.enable || matches != [ ];
    builtins.head matches;
in
{
  options.services.crowdsec = {
    # lapiConnect = lib.mkOption {
    #   type = lib.types.submodule ({
    #     options = {
    #       enable = (lib.mkEnableOption "sending sensor data to LAPI on another host") // {
    #         default = true;
    #       };

    #       url = lib.mkOption {
    #         type = lib.types.str;
    #         description = ''
    #           URL pointing to the host that runs the crowdsec LAPI in master mode.
    #         '';
    #       };

    #       name = lib.mkOption {
    #         type = lib.types.str;
    #         default = config.networking.hostName;
    #         description = ''
    #           Name of the current host, also used as username, that identifies this crowdsec engine to the master LAPI.
    #         '';
    #       };

    #       passwordFile = lib.mkOption {
    #         type = lib.types.nullOr (
    #           lib.types.pathWith {
    #             inStore = false;
    #             absolute = true;
    #           }
    #         );
    #         description = ''
    #           Location of the file where the authentication password is stored to fetch decisions from the master LAPI.
    #         '';
    #       };
    #     };
    #   });
    #   default = {
    #     enable = false;
    #   };
    #   description = ''
    #     Configure this crowdsec engine as a slave to a Crowdsec Local API (LAPI) running on another host.
    #     See <https://docs.crowdsec.net/u/user_guides/multiserver_setup> for details about multi-server setup.
    #   '';
    #   example = {
    #     url = "https://my-lapi-server";
    #     name = "sensor-01";
    #     passwordFile = "/run/secrets/sensor-01-key";
    #   };
    # };

    sensors = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              # TODO; Add enable option and add/remove based on bool value

              machineName = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "User friendly name (also username) of the crowdsec engine reporting to this host";
                example = "Jeff";
              };

              passwordFile = lib.mkOption {
                type = lib.types.nullOr (
                  lib.types.pathWith {
                    inStore = false;
                    absolute = true;
                  }
                );
                default = null;
                description = ''
                  File holding the login secret for the crowdsec engine reporting to this host.  
                  This value can be null if you configured the LAPI to allow auto-registration.
                  See <https://docs.crowdsec.net/u/user_guides/multiserver_setup/#lapi> for details about auto-registration.
                '';
                example = "/run/secrets/sensor-password";
              };
            };
          }
        )
      );
      default = { };
      description = ''
        A set of crowdsec engines that report their detections to this host.
        See <https://docs.crowdsec.net/u/user_guides/multiserver_setup/#introduction> for details.
      '';
      example = {
        sensor-01.passwordFile = "<path outside of nix store>";
      };
    };

    bouncers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              # TODO; Add enable option and add/remove based on bool value

              machineName = lib.mkOption {
                type = lib.types.str;
                description = "User friendly name (also username) of the software (firewall handler and others) acting on decisions";
                example = "Jeff";
              };

              passwordFile = lib.mkOption {
                type = lib.types.pathWith {
                  inStore = false;
                  absolute = true;
                };
                description = ''
                  File holding the login secret that the bouncer software uses to connect with to the local API.
                '';
                example = "/run/secrets/bouncer-password";
              };
            };

            # Set default username
            config.machineName = name;
          }
        )
      );
      default = { };
      description = ''
        A set of crowdsec bouncer registrations, software that acts upon ban decisions.
        See <https://docs.crowdsec.net/u/user_guides/bouncers_configuration/> for details.
      '';
      example = {
        local-firewall.passwordFile = "<path outside of nix store>";
      };
    };

    extraSetupCommands = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional shell commands appended to the setup script";
      example = ''
        ## Collections
        cscli collections install \
          crowdsecurity/linux \
          crowdsecurity/nginx
      '';
    };
  };

  config = lib.mkIf cfg.enable ({
    assertions = [
      ({
        assertion =
          (cfg.sensors != { } -> cfg.settings.general.api.server.enable)
          && (cfg.bouncers != { } -> cfg.settings.general.api.server.enable);
        message = ''
          The LAPI service must be enabled to configure a distributed setup. Your sensors/bouncers have currently no master service to connect to.
          To fix this issue, enable LAPI by setting `services.crowdsec.settings.general.api.server.enable` to true.
        '';
      })
      # ({
      #   assertion = cfg.settings.api.server.enable -> !cfg.lapiConnect.enable;
      #   message = ''
      #     The crowdsec engine cannot be configured as LAPI master and slave at the same time.
      #     To fix this issue either;
      #       - Disable the LAPI by setting `services.crowdsec.settings.api.server.enable` to false
      #       - Disable LAPI slave mode by setting `services.crowdsec.lapiConnect.enable` to false
      #   '';
      # })
      # ({
      #   assertion = !cfg.settings.api.server.enable -> cfg.lapiConnect.enable;
      #   message = ''
      #     The crowdsec engine must be configured with a destination for sensor alerts.
      #     To fix this issue either;
      #       - Enable LAPI by setting `services.crowdsec.settings.api.server.enable` to true
      #       - Setup LAPI slave mode by configuring `services.crowdsec.lapiConnect` with data from a LAPI master
      #   '';
      # })
    ];

    systemd.targets.crowdsec = {
      description = lib.mkDefault "Crowdsec";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "crowdsec.service"
        "crowdsec-setup.service"
      ];
    };

    systemd.services.crowdsec-update-hub = {
      # NOTE; Reload configuration is disabled upstream due to database connection leaks
      # NOTE; Must restart as root, because service is running as low priviliged user (crowdsec)
      serviceConfig.ExecStartPost = lib.mkForce "+systemctl restart crowdsec.service";
    };

    systemd.services.crowdsec = {
      partOf = [ config.systemd.targets.crowdsec.name ];

      # # ERROR; Reloading crowdsec after updates causes the log to be spammed with 'unable to fetch scenarios from db: XXX'
      # # REF; https://github.com/crowdsecurity/crowdsec/issues/656
      # # reloadTriggers = [ configFile ];
      # restartTriggers = [ configFile ];

      # serviceConfig = {
      #   # ERROR; NOT notify-reload because ExecReload is manually defined.
      #   # Running the ExecReload commands is mutually exclusive with the ReloadSignal.
      #   Type = "notify";

      #   # Give crowdsec limited time to shutdown after receiving systemd's stop signal.
      #   TimeoutSec = 20;
      #   RestartSec = 60; # Value copied from crowdsec repo

      #   ExecStartPre = lib.mkMerge [
      #     (lib.mkBefore (
      #       lib.optional cfg.lapiConnect.enable "${pkgs.writeShellScriptBin "register-to-lapi" ''
      #         set -e

      #         if [ ! -s '${cfg.settings.api.client.credentials_path}' ]; then
      #           # ERROR; Cannot use 'cscli lapi register ..' because that command wants a valid local_api_credentials file, which we
      #           # want to create as new with that same command.. /facepalm
      #           cat > '${cfg.settings.api.client.credentials_path}' <<EOF
      #         url: ${cfg.lapiConnect.url}
      #         login: ${cfg.lapiConnect.name}
      #         password: ''$(cat '${cfg.lapiConnect.passwordFile}')
      #         EOF
      #           echo "This crowdsec instance is configured to send alerts to LAPI at '${cfg.lapiConnect.url}'"
      #         fi

      #         # ERROR; Hub update is only executed when online credentials are set, but this is _not_ a requirement.
      #         # This should be fixed upstream!
      #         cscli hub update
      #       ''}/bin/register-to-lapi"
      #     ))
      #     (lib.mkAfter [
      #       # Checks completed configuration before starting daemon
      #       "${cfg.package}/bin/crowdsec -c /etc/crowdsec/config.yaml -t -error"
      #     ])
      #   ];

      #   # NOTE; Overwritten because the configuration file got symlinked!
      #   ExecStart = lib.mkForce "${cfg.package}/bin/crowdsec -c /etc/crowdsec/config.yaml";

      #   # Configuration reloading allows crowdsec to use newly setup configuration without going through the stop/start state machine.
      #   # The state machine will restart all services linked to the target and/or service causing disruption.
      #   # To make reloading work we need to symlink the configuration file, see services.haproxy for a straightforward example.
      #   ExecReload = [
      #     "${cfg.package}/bin/crowdsec -c /etc/crowdsec/config.yaml -t -error"
      #     # WARN; Asynchronous signal, not good for service ordering. But assumed to succeed shortly after because
      #     # the configuration is already validated at this point.
      #     "${pkgs.coreutils}/bin/kill -HUP $MAINPID"
      #   ];
      # };

      # unitConfig =
      #   let
      #     inherit (config.systemd.services.crowdsec.serviceConfig) TimeoutSec;
      #     maxTries = 5;
      #     bufferSec = 5;
      #   in
      #   {
      #     # The max. time needed to perform `maxTries` start attempts of systemd
      #     # plus a bit of buffer time (bufferSec) on top.
      #     StartLimitIntervalSec = TimeoutSec * maxTries + bufferSec;
      #     StartLimitBurst = maxTries;
      #   };
    };

    systemd.services.crowdsec-setup = {
      description = "Crowdsec LAPI setup";

      requires = [ config.systemd.services.crowdsec.name ];
      after = [ config.systemd.services.crowdsec.name ];

      path = [
        cscli
        pkgs.coreutils
      ];

      # NOTE; Do not set in nixpkgs(repo) modules, to be controlled by option systemd.enableStrictShellChecks
      enableStrictShellChecks = true;

      script = (builtins.readFile ./lapi-setup.sh) + ''
        # NOTE; Don't remove this comment line, a newline is required here

        ${lib.optionalString cfg.settings.general.api.server.enable ''
          # If the engine is configured to connect to a remote LAPI and connecting fails, the crowdsec service itself fails.
          # If the engine is configured as standalone/master LAPI, wait until it's initialised fully.
          wait_for_lapi
        ''}

        ${lib.concatMapAttrsStringSep "\n" (
          _: sensor: "add_machine_cscli '${sensor.machineName}' '${sensor.passwordFile}'"
        ) cfg.sensors}
        ${lib.concatMapAttrsStringSep "\n" (
          _: bouncer: "add_bouncer_cscli '${bouncer.machineName}' '${bouncer.passwordFile}'"
        ) cfg.bouncers}

        ${cfg.extraSetupCommands}
      '';

      postStart = ''
        # NOTE; Explicit reload as to not go through stop/start jobs and trigger the service state machine chain
        # ERROR; Do not restart, restarting is at this point (in time) incompatible with the "requires" unit dependency from
        # crowdsec-setup to crowdsec service.
        # NOTE; systemctl control requires more elevated permissions!

        # ERROR; Reloading crowdsec after updates causes the log to be spammed with 'unable to fetch scenarios from db: XXX'
        # REF; https://github.com/crowdsecurity/crowdsec/issues/656
        # systemctl reload ${config.systemd.services.crowdsec.name}
      '';

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  });
}
