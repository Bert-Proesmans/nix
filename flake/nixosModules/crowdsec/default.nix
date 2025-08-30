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
in
{
  imports = [
    flake.inputs.crowdsec.nixosModules.crowdsec
  ];

  options.services.crowdsec = {
    sensors = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
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
              machineName = lib.mkOption {
                type = lib.types.str;
                default = name;
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
        assertion = cfg.acquisitions != [ ];
        message = ''
          The crowdsec engine fails to start without acquisitions.
          To fix this issue, add at least one acquisition source to option services.crowdsec.acquisitions.
        '';
      })
    ];

    # configuration file indirection is needed to support reloading
    environment.etc."crowdsec.yaml".source = configFile;

    systemd.targets.crowdsec = {
      description = "Crowdsec";
      wantedBy = [ "multi-user.target" ];
      requires = [
        config.systemd.services.crowdsec.name
        config.systemd.services.crowdsec-setup.name
        # TODO; Add firewall-bouncer if enabled
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

        ExecStartPre = lib.mkAfter [
          # Checks completed configuration before starting daemon
          "${cfg.package}/bin/crowdsec -c /etc/crowdsec.yaml -t -error"
        ];

        # NOTE; Overwritten because the configuration file got symlinked!
        ExecStart = lib.mkForce "${cfg.package}/bin/crowdsec -c /etc/crowdsec.yaml";

        # Configuration reloading allows crowdsec to use newly setup configuration without going through the stop/start state machine.
        # The state machine will restart all services linked to the target and/or service causing disruption.
        # To make reloading work we need to symlink the configuration file, see services.haproxy for a straightforward example.
        ExecReload = [
          "${cfg.package}/bin/crowdsec -c /etc/crowdsec.yaml -t -error"
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
        ${lib.concatMapAttrsStringSep "\n" (
          _: sensor: "add_machine_cscli '${sensor.machineName}' '${sensor.passwordFile}'"
        ) cfg.sensors}
        ${lib.concatMapAttrsStringSep "\n" (
          _: bouncer: "add_bouncer_cscli '${bouncer.machineName}' '${bouncer.passwordFile}'"
        ) cfg.bouncers}

        ${cfg.extraSetupCommands}
      '';
    };
  });
}
