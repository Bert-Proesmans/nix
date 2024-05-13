{ outputs }:
let
  inherit (outputs) profiles;
in
{ lib, pkgs, config, ... }:
let
  cfg = config.proesmans.install-script;

  # Converts hostname to the required attribute to install the system
  # This approach also checks for attribute existance, and automatically includes the necessary closure
  # into the installation medium!
  toplevel-build = host-attribute: outputs.nixosConfigurations."${host-attribute}".config.system.build.toplevel;
  disko-script = host-attribute: outputs.nixosConfigurations."${host-attribute}".config.system.build.diskoScript;
in
{
  options.proesmans.install-script = {
    enable = lib.mkEnableOption "Installer script" // {
      description = ''
        Configures a script named "install-system" that formats disks and installs the host configuration of host-attribute.
      '';
    };
    host-attribute = lib.mkOption {
      type = lib.types.str;
      example = "development";
      description = lib.mdDoc ''
        Attribute name of the host to install. This host must be defined within this flake, at path `.#nixosConfigurations.<hostname>`!
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.getty.helpLine = lib.mkAfter ''
      This machine has been configured with an installer script, run 'install-system' to (ya-know) install the system ☝️
    '';

    environment.systemPackages = [
      (
        let
          install-system-script = pkgs.writeShellApplication {
            name = "inner-install-system";
            runtimeInputs = [ pkgs.nix pkgs.nixos-install-tools ]; # Cannot use pkgs.sudo, for workaround see 'export PATH' below
            text = ''
              # Fun fact; Sudo does not work in a pure shell. It fails with error 'sudo must be owned by uid 0 and have the setuid bit set'
              # Nixos has someting called security wrappers (nixos option security.wrapper) which perform additional 
              # setup during the shell init, wrapping sudo and other security related binaries.
              # The export below pulls in all programs that were wrapped by the system configuration. Impure, sadly..
              export PATH="${config.security.wrapperDir}:$PATH"
                        
              echo "# Install wrapper started"

              sudo "${(disko-script cfg.host-attribute)}"
                echo "# Disks formatted"
              
              # NOTE; '0' as value for cores means "use all available cores"
              sudo nixos-install --no-channel-copy --no-root-password --max-jobs 4 --cores 0 \
              --system "${(toplevel-build cfg.host-attribute)}"
                echo "# System installed"

              echo "# Script done"
            '';
          };
        in
        # Wrapper script for capturing the output of the actual installation progress
        pkgs.writeShellApplication {
          name = "install-system";
          runtimeInputs = [ install-system-script ];
          text = ''
            # Create a temporary log file with a unique name
            log_file="$(mktemp -t install-system.XXXXXX.log)"

            # Execute the wrapped script, capturing both stdout and stderr
            "${lib.getExe install-system-script}" 2>&1 | tee "$log_file"

            echo "Execution log is saved at: $log_file"
          '';
        }
      )
    ];
  };
}
