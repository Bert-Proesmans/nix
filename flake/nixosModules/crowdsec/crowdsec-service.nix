{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.crowdsec;

  # Hardcoded upstream
  format = pkgs.formats.yaml { };
  configFile = format.generate "crowdsec.yaml" cfg.settings.general;
  confDir = "/etc/crowdsec/";

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
    cscliPackage = lib.mkOption {
      type = lib.types.package;
      default = cscli;
      description = "The package with binary to invoke the crowdsec CLI";
      readOnly = true;
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
    ];

    systemd.tmpfiles.settings = {
      "11-crowdsec" = {
        # ERROR; cscli explain doesn't take the reference to the configuration file location and falls back to the default one..
        # The config file is linked into the default location as workaround.
        "${lib.strings.normalizePath "${confDir}/config.yaml"}"."L+".argument = "${configFile}";
      };
    };

    proesmans.nix.overlays = [
      # ERROR; Doesn't work on its own, the service crowdsec-lapi-setup triggers instantly.
      # ..this needs more tweaks to the package recipe!
      # TODO; Fix
      # (_final: prev: {
      #   crowdsec = prev.crowdsec.overrideAttrs (old: {
      #     # Add systemd libs to build environment so unit type "notify" works as expected.
      #     buildInputs = (old.buildInputs or [ ]) ++ [ prev.systemd ];

      #     # Speed up build completion because this always builds locally
      #     doCheck = false;
      #   });
      # })
    ];

    systemd.targets.crowdsec = {
      description = lib.mkDefault "Crowdsec";
      wantedBy = [ "multi-user.target" ];
      requires = [ config.systemd.services.crowdsec.name ];
      wants = lib.optionals (config.systemd.services.crowdsec-lapi-setup.enable) [
        config.systemd.services.crowdsec-lapi-setup.name
      ];
    };

    systemd.services.crowdsec-update-hub = {
      enable = cfg.autoUpdateService;
      # NOTE; Reload configuration is disabled upstream due to database connection leaks
      # NOTE; Must restart as root, because service is running as low priviliged user (crowdsec)
      serviceConfig.ExecStartPost = lib.mkForce "+systemctl restart crowdsec.target";
    };

    systemd.services.crowdsec = {
      partOf = [ config.systemd.targets.crowdsec.name ];

      serviceConfig = {
        # Give crowdsec limited time to shutdown after receiving systemd's stop signal.
        TimeoutSec = 20;
        RestartSec = 60; # Value copied from crowdsec repo
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

    systemd.services.crowdsec-lapi-setup = {
      enable = cfg.settings.general.api.server.enable;
      description = "Crowdsec LAPI configuration";

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

        ${lib.optionalString (cfg.settings.general.api.server.enable) ''
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
