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
  cscli = pkgs.writeShellApplication {
    name = "cscli";
    runtimeInputs = [ cfg.package ];
    text = ''
      exec cscli -c=${configFile} "''${@}"
    '';
  };
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
                  File holding the login secret for the crowdsec engine reporting to this host. This value can be null if you configured the LAPI to allow auto-registration.
                  See <https://docs.crowdsec.net/u/user_guides/multiserver_setup/#lapi> for details.
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
                  File holding the login secret for the crowdsec engine reporting to this host. This value can be null if you configured the LAPI to allow auto-registration.
                  See <https://docs.crowdsec.net/u/user_guides/multiserver_setup/#lapi> for details.
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

          add-machine-cscli = pkgs.writeShellApplication {
            name = "add-machine-cscli";
            runtimeInputs = [ cscli ];
            text = ''
              if [ "$#" -ne 2 ]; then
                echo "usage: $0 <machinename> <passwordfile>" >&2
                exit 1
              fi

              machinename="$1"
              passwordfile="$2"

              # This command activates a self-service registered sensor
              # And also acts as a status check
              if cscli machines validate "$machinename" >/dev/null; then
                echo "Machine '$machinename' exists with valid data, skipping add"
                exit 0
              fi

              if [ ! -r "$passwordfile" ]; then
                echo "error: password file '$passwordfile' not readable" >&2
                exit 2
              fi

              # The idiocy of this tool to not accept a file with a password is unbelievable.
              # The fuckery I need to do to workaround is just stupid.

              exec 3> >(cat >/dev/null)

              # TODO; Fix the password leak in process list
              password=$(cat "$passwordfile")
              cscli machines add "$machinename" --password "$password" --force --file - >&3
              exit_code=$?

              exec 3>&-
              exit $exit_code
            '';
          };

          setup-sensors = pkgs.writeShellApplication {
            name = "setup-sensors";
            runtimeInputs = [ add-machine-cscli ];
            text = lib.concatMapAttrsStringSep "\n" (
              _: sensor: "add-machine-cscli '${sensor.machineName}' '${sensor.passwordFile}'"
            ) cfg.sensors;
          };

          add-bouncer-cscli = pkgs.writeShellApplication {
            name = "add-bouncer-cscli";
            runtimeInputs = [ cscli ];
            text = ''
              if [ "$#" -ne 2 ]; then
                echo "usage: $0 <machinename> <passwordfile>" >&2
                exit 1
              fi

              machinename="$1"
              passwordfile="$2"

              if cscli bouncers inspect "$machinename" >/dev/null; then
                echo "Bouncer '$machinename' exists with valid data, skipping add"
                exit 0
              fi

              if [ ! -r "$passwordfile" ]; then
                echo "error: password file '$passwordfile' not readable" >&2
                exit 2
              fi

              # The idiocy of this tool to not accept a file with a password is unbelievable.
              # The fuckery I need to do to workaround is just stupid.

              # TODO; Fix the password leak in process list
              password=$(cat "$passwordfile")
              cscli bouncers add "$machinename" --key "$password" >/dev/null

              exit $?
            '';
          };

          setup-bouncers = pkgs.writeShellApplication {
            name = "setup-bouncers";
            runtimeInputs = [ add-bouncer-cscli ];
            text = lib.concatMapAttrsStringSep "\n" (
              _: bouncer: "add-bouncer-cscli '${bouncer.machineName}' '${bouncer.passwordFile}'"
            ) cfg.bouncers;
          };
        in
        lib.mkMerge [
          (lib.mkBefore [ (lib.getExe waitForStart) ])
          # Currently no upstream/default PostStart script, but this is forwards compatible
          (lib.mkAfter (
            lib.optional (cfg.sensors != { }) (lib.getExe setup-sensors)
            ++ lib.optional (cfg.bouncers != { }) (lib.getExe setup-bouncers)
          ))
        ];
    };
  });
}
