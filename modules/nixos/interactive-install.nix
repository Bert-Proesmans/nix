{ lib, config, pkgs, target-host, ... }:
let
    cfg = config.my.interactive-install;
in {
    options.my.interactive-install.enable = lib.mkEnableOption ("Provision scripts for manual/interactive install") // {
        default = true;
    };

    config = 
        let
            system-closure = target-host.config.system.build.toplevel;
            disko-format = pkgs.writeShellScriptBin "disko-format" "${target-host.config.system.build.formatScript}";
            disko-mount = pkgs.writeShellScriptBin "disko-mount" "${target-host.config.system.build.mountScript}";

            install-system = pkgs.writeShellScriptBin "install-system" ''
                set -euo pipefail
                echo "# Install wrapper started"

                . ${disko-format}/bin/disko-format
                echo "# Disks formatted"

                . ${disko-mount}/bin/disko-mount
                echo "# Disks and partitions mounted"

                nixos-install --system ${system-closure}
                echo "# Target system installed"

                echo "# Done"
            '';
        in lib.mkIf cfg.enable 
         {
            environment.systemPackages = [ disko-mount disko-format install-system ];
        };
}
