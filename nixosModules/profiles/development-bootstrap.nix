{ lib, pkgs, flake-inputs, config, ... }: {
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
      devShells = flake-inputs.self.outputs.devShells."${system}";

      deployment-script = pkgs.writeShellApplication {
        name = "develop-host-install";
        runtimeInputs = [ pkgs.nix ];
        # ERROR; The host-deploy task must know how to deploy the hostconfiguration
        # by name "development" !
        text = ''
          nix develop ${devShells.deployment-shell} \
            --command bash \
            -c "invoke host-deploy development root@localhost"
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
