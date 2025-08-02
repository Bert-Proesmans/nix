{
  lib,
  pkgs,
  flake,
  config,
  ...
}:
{
  # WARN; Using this installer is not recommended, but required to bootstrap at least a development machine.
  # You should use the development host to provision new hosts!
  #
  # NOTE; The installation of a host is complex because secrets need to be copied after installation.
  # The full installation procedure is recorded within tasks.py, and I'm not going to reproduce it here
  # in bash.
  # That means procedure in this file calls that task.py file, resulting in lots of wrapping and
  # (possibly) flaky behaviour.
  #
  environment.systemPackages =
    let
      system = config.nixpkgs.hostPlatform.system;
      # ERROR; nix develop does not work with derivation outPaths! We must pass it a derivation by itself.
      #
      # WARN; To ensure the development shell exists, its full attribute path is evaluated. Afterwards
      # the interactive string reference is returned that points to the same derivation.
      devShells =
        shell-attribute:
        (builtins.seq flake.outputs.devShells."${system}"."${shell-attribute}"
          "${flake}#${shell-attribute}"
        );

      deployment-script = pkgs.writeShellApplication {
        name = "develop-host-install";
        runtimeInputs = [
          pkgs.nix
          pkgs.openssh
        ];
        # ERROR; The host-deploy task must know how to deploy the hostconfiguration
        # by name "development" !
        text = ''
          if ! ssh-add -L >/dev/null 2>&1
          then
            echo "-- WARNING --"
            echo "No SSH keys were found, so you'll have to use password login. Make sure to set a root password with \`sudo passwd\`"
          fi

          nix develop "${devShells "deployment-shell"}" \
            --command bash \
            -c "invoke --search-root ${flake} deploy development root@localhost"
        '';
      };

      # NOTE; Must be run from interactive shell!
      installer = pkgs.writeShellApplication {
        name = "install-system";
        runtimeInputs = [ deployment-script ];
        text = ''
          log_file="$(mktemp -t install-system.XXXXXX.log)"

          trap 'echo "The full log journal can be found at path: $log_file"' EXIT

          # Execute the wrapped script, capturing both stdout and stderr
          "${lib.getExe deployment-script}" 2>&1 | tee "$log_file"

          echo "Execution log is saved at: $log_file"
        '';
      };
    in
    [ installer ];
}
