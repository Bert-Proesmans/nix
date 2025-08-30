{
  flake,
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.crowdsec;

  # Hardcoded upstream
  state-dir-crowdsec = "/Var/lib/crowdsec";
  format = pkgs.formats.yaml { };
  configFile = format.generate "crowdsec.yaml" cfg.settings;
  user = "crowdsec";
  group = "crowdsec";
in
{
  imports = [
    flake.inputs.crowdsec.nixosModules.crowdsec
  ];

  options.services.crowdsec = {
    lapiConnect = lib.mkOption {
      type = lib.types.submodule ({
        options = {
          enable = (lib.mkEnableOption "sending sensor data to LAPI on another host") // {
            default = true;
          };

          url = lib.mkOption {
            type = lib.types.str;
            description = ''
              URL pointing to the host that runs the crowdsec LAPI in master mode.
            '';
          };

          name = lib.mkOption {
            type = lib.types.str;
            default = config.networking.hostName;
            description = ''
              Name of the current host, also used as username, that identifies this crowdsec engine to the master LAPI.
            '';
          };

          passwordFile = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.pathWith {
                inStore = false;
                absolute = true;
              }
            );
            description = ''
              Location of the file where the authentication password is stored to fetch decisions from the master LAPI.
            '';
          };
        };
      });
      default = {
        enable = false;
      };
      description = ''
        Configure this crowdsec engine as a slave to a Crowdsec Local API (LAPI) running on another host.
        See <https://docs.crowdsec.net/u/user_guides/multiserver_setup> for details about multi-server setup.
      '';
      example = {
        url = "https://my-lapi-server";
        name = "sensor-01";
        passwordFile = "/run/secrets/sensor-01-key";
      };
    };

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

    additionalParsers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              # TODO; Should this delete on value 'false'?
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = ''
                  Whether this file should be linked into the parsers configuration.
                '';
              };

              target = lib.mkOption {
                type = lib.types.str;
                description = ''
                  Name of symlink (relative to the crowdsec parsers directory).  Defaults to the attribute name.
                '';
              };

              source = lib.mkOption {
                type = lib.types.path;
                description = ''
                  Parser definition.
                  See <https://docs.crowdsec.net/docs/next/log_processor/parsers/create/> for an explanation about the parser schema.
                '';
                example = lib.literalExpression ''
                  writeTextDir "parsers/my-simple-parser.yaml" '''
                    # Very simple parser (that does nothing)
                    filter: 1 == 1
                    debug: true
                    onsuccess: next_stage
                    name: crowdsecurity/myservice-logs
                    description: "Parse myservice logs"
                    grok:
                        #our grok pattern : capture .*
                        pattern: ^%{DATA:some_data}$
                        #the field to which we apply the grok pattern : the log message itself
                        apply_on: message
                    statics:
                        - parsed: is_my_service
                          value: yes
                  ''';
                '';
              };
            };

            # Set default filename
            config.target = name;
          }
        )
      );
      default = { };
      description = ''
        <TODO>
        See <https://wheresalice.info/main/tech/crowdsec-custom-logs> for a quickstart on custom parsers.
        See <https://docs.crowdsec.net/u/user_guides/cscli_explain/> for help on debugging parsers.
      '';
      example = lib.literalExpression ''
        {
          "s01-parse/sshd-logs.yaml".source = ./parsers/sshd-logs.yaml;
        }
      '';
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
        assertion = cfg.acquisitions != [ ];
        message = ''
          The crowdsec engine fails to start without acquisitions.
          To fix this issue, add at least one acquisition source to option services.crowdsec.acquisitions.
        '';
      })
      ({
        assertion =
          (cfg.sensors != { } -> cfg.settings.api.server.enable)
          && (cfg.bouncers != { } -> cfg.settings.api.server.enable);
        message = ''
          The LAPI service must be enabled to configure a distributed setup. Your sensors/bouncers have currently no master service to connect to.
          To fix this issue, enable LAPI by setting `services.crowdsec.settings.api.server.enable` to true.
        '';
      })
      ({
        assertion = cfg.additionalParsers != { } -> cfg.settings.crowdsec_service.enable;
        message = ''
          The log processor must be enabled. Your parsers are currently not being processed.
          To fix this issue, enable the log processor by setting `services.crowdsec.settings.crowdsec_service.enable` to true.
        '';
      })
      ({
        assertion = cfg.settings.api.server.enable -> !cfg.lapiConnect.enable;
        message = ''
          The crowdsec engine cannot be configured as LAPI master and slave at the same time.
          To fix this issue either;
            - Disable the LAPI by setting `services.crowdsec.settings.api.server.enable` to false
            - Disable LAPI slave mode by setting `services.crowdsec.lapiConnect.enable` to false
        '';
      })
      ({
        assertion = !cfg.settings.api.server.enable -> cfg.lapiConnect.enable;
        message = ''
          The crowdsec engine must be configured with a destination for sensor alerts.
          To fix this issue either;
            - Enable LAPI by setting `services.crowdsec.settings.api.server.enable` to true
            - Setup LAPI slave mode by configuring `services.crowdsec.lapiConnect` with data from a LAPI master
        '';
      })
    ];

    # configuration file indirection is needed to support reloading
    environment.etc."crowdsec/config.yaml".source = configFile;

    systemd.targets.crowdsec = {
      description = lib.mkDefault "Crowdsec";
      wantedBy = [ "multi-user.target" ];
      requires = [
        config.systemd.services.crowdsec.name
        config.systemd.services.crowdsec-setup.name
      ];
    };

    systemd.services.crowdsec-update-hub = {
      serviceConfig = {
        User = "crowdsec";
        Group = "crowdsec";
        Type = lib.mkForce "oneshot";
        RemainAfterExit = lib.mkForce false;
        # ERROR; The direct commands MUST BE resolved paths to an executable! Hence writeShellScriptBin
        ExecStart =
          let
            update-crowdsec-hub = pkgs.writeShellScriptBin "update-crowdsec-hub" ''
              set -e
              cscli --error hub upgrade
            '';
          in
          lib.mkForce (lib.getExe update-crowdsec-hub);
        ExecStartPost =
          let
            restart-crowdsec = pkgs.writeShellScriptBin "restart-crowdsec" ''
              set -e
              # NOTE; Explicitly restart crowdsec so setup is re-run after initializing
              # NOTE; Only restart the service if it was already running
              systemctl try-restart ${config.systemd.services.crowdsec.name}
            '';
          in
          lib.mkForce (
            # Runs as root
            "+" + (lib.getExe restart-crowdsec)
          );
      };
    };

    systemd.services.crowdsec = {
      # To trigger the .target also on "systemctl start crowdsec" as well as on
      # restarts & stops.
      # Please note that crowdsec.service & crowdsec.target binding to
      # each other makes the Restart=always rule racy and results
      # in sometimes the service not being restarted.
      wants = [ config.systemd.targets.crowdsec.name ];
      partOf = [ config.systemd.targets.crowdsec.name ];

      # ERROR; Reloading crowdsec after updates causes the log to be spammed with 'unable to fetch scenarios from db: XXX'
      # REF; https://github.com/crowdsecurity/crowdsec/issues/656
      # reloadTriggers = [ configFile ];
      restartTriggers = [ configFile ];

      serviceConfig = {
        # ERROR; NOT notify-reload because ExecReload is manually defined.
        # Running the ExecReload commands is mutually exclusive with the ReloadSignal.
        Type = "notify";

        # Give crowdsec limited time to shutdown after receiving systemd's stop signal.
        TimeoutSec = 20;
        RestartSec = 60; # Value copied from crowdsec repo

        ExecStartPre = lib.mkMerge [
          (lib.mkBefore (
            lib.optional cfg.lapiConnect.enable "${pkgs.writeShellScriptBin "register-to-lapi" ''
              set -e

              if [ ! -s '${cfg.settings.api.client.credentials_path}' ]; then
                # ERROR; Cannot use 'cscli lapi register ..' because that command wants a valid local_api_credentials file, which we
                # want to create as new with that same command.. /facepalm
                cat > '${cfg.settings.api.client.credentials_path}' <<EOF
              url: ${cfg.lapiConnect.url}
              login: ${cfg.lapiConnect.name}
              password: ''$(cat '${cfg.lapiConnect.passwordFile}')
              EOF
                echo "This crowdsec instance is configured to send alerts to LAPI at '${cfg.lapiConnect.url}'"
              fi

              # ERROR; Hub update is only executed when online credentials are set, but this is _not_ a requirement.
              # This should be fixed upstream!
              cscli hub update
            ''}/bin/register-to-lapi"
          ))
          (lib.mkAfter [
            # Checks completed configuration before starting daemon
            "${cfg.package}/bin/crowdsec -c /etc/crowdsec/config.yaml -t -error"
          ])
        ];

        # NOTE; Overwritten because the configuration file got symlinked!
        ExecStart = lib.mkForce "${cfg.package}/bin/crowdsec -c /etc/crowdsec/config.yaml";

        # Configuration reloading allows crowdsec to use newly setup configuration without going through the stop/start state machine.
        # The state machine will restart all services linked to the target and/or service causing disruption.
        # To make reloading work we need to symlink the configuration file, see services.haproxy for a straightforward example.
        ExecReload = [
          "${cfg.package}/bin/crowdsec -c /etc/crowdsec/config.yaml -t -error"
          # WARN; Asynchronous signal, not good for service ordering. But assumed to succeed shortly after because
          # the configuration is already validated at this point.
          "${pkgs.coreutils}/bin/kill -HUP $MAINPID"
        ];
      };

      unitConfig =
        let
          inherit (config.systemd.services.crowdsec.serviceConfig) TimeoutSec;
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

    systemd.services.crowdsec-setup = {
      description = "Crowdsec LAPI setup";

      requires = [ config.systemd.services.crowdsec.name ];
      after = [ config.systemd.services.crowdsec.name ];

      serviceConfig = {
        User = "crowdsec";
        Group = "crowdsec";
        Type = "oneshot";
        RemainAfterExit = true;

        # NOTE; Installation of overflows requires crowdsec reloading its configuration!
        ExecStartPost =
          let
            reload-crowdsec = pkgs.writeShellScriptBin "reload-crowdsec" ''
              set -e

              # NOTE; Explicit reload as to not go through stop/start jobs and trigger the service state machine chain
              # ERROR; Do not restart, restarting is at this point (in time) incompatible with the "requires" unit dependency from
              # crowdsec-setup to crowdsec service.

              # ERROR; Reloading crowdsec after updates causes the log to be spammed with 'unable to fetch scenarios from db: XXX'
              # REF; https://github.com/crowdsecurity/crowdsec/issues/656
              # systemctl reload ${config.systemd.services.crowdsec.name}
            '';
          in
          lib.mkForce (
            # Runs as root
            "+" + (lib.getExe reload-crowdsec)
          );
      };

      path = config.systemd.services.crowdsec.path ++ [ pkgs.coreutils ];

      # NOTE; Do not set in modules library, to be controlled by option systemd.enableStrictShellChecks
      enableStrictShellChecks = true;

      script = (builtins.readFile ./lapi-setup.sh) + ''
        # NOTE; Don't remove this comment, a newline is required here
        ${lib.optionalString cfg.settings.api.server.enable ''
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
    };

    # NOTE; No need to order after "systemd-tmpfiles-setup.service" because the default dependencies of all service units contains
    # sysinit.target which is ordered after "systemd-tmpfiles-setup.service"!
    systemd.tmpfiles.rules =
      let
        parsers-directory = "${cfg.settings.config_paths.config_dir}/parsers";
      in
      lib.mkIf (cfg.additionalParsers != { }) (
        [
          "d '${parsers-directory}' 0750 ${user} ${group} - -"
          "d '${parsers-directory}/s00-raw' 0750 ${user} ${group} - -"
          "d '${parsers-directory}/s01-parse' 0750 ${user} ${group} - -"
          "d '${parsers-directory}/s02-enrich' 0750 ${user} ${group} - -"
        ]
        ++ (lib.pipe cfg.additionalParsers [
          (lib.filterAttrs (_: v: v.enable))
          # NOTE; Create parent directory + symlink
          (lib.mapAttrsToList (
            _: v: [
              "d '${builtins.dirOf "${parsers-directory}/${v.target}"}' 0750 ${user} ${group} - -"
              # ERROR; Quotes in the 7th (last) field will be verbatim copied over. Do _not_ quote the source path!
              # REF; https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html#Configuration%20File%20Format
              "L+ '${parsers-directory}/${v.target}' - - - - ${v.source}"
            ]
          ))
          (lib.flatten)
        ])
      );
  });
}
