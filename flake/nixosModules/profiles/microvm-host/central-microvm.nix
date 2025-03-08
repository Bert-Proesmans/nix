{ lib, config, ... }: {
  config = {
    systemd.mounts = lib.flatten (lib.flip lib.mapAttrsToList config.microvm.vms (
      name: microvm-config: [{
        # INFO; Mount a base directory for our merged mounting layout

        # RAMfs does not support posix ACL nor size limits!
        what = "tmpfs";
        where = "/run/central-microvm/${name}";
        type = "tmpfs";
        options = lib.concatStringsSep "," [
          # NOTE; Remount the filesystem as read-only after provisioning!
          # mount -o remount,ro /shared
          "rw"
          #
          # ERROR; Cannot set to 0, that would prevent us from creating directories
          # Directories are required as bind mount target
          # NOTE; Should remount /shared as read-only!
          "size=1M"
          #
          # More mounting options for security/robustness
          "mode=0700"
          "uid=0"
          "gid=0"
          "noswap"
          "nosuid"
          "nodev"
          "noatime"
        ];

        before = [
          "microvm@${name}.service"
          "microvm-tap-interfaces@${name}.service"
          "microvm-pci-devices@${name}.service"
          "microvm-virtiofsd@${name}.service"
        ];
        requiredBy = [ "microvm@${name}.service" ];
        partOf = [ "microvm@${name}.service" ];
      }]
      ++ (lib.flip builtins.map microvm-config.config.config.microvm.central.shares (
        share: {
          # INFO; Mount each desired directory into the base

          what = share.source;
          where = "/run/central-microvm/${name}/${share.tag}";
          type = "none";
          options = lib.concatStringsSep "," (
            [ "bind" ]
              ++ lib.optionals share.read-only [ "ro" ]
          );

          unitConfig.RequiresMountsFor = [ "/run/central-microvm/${name}" ];
          before = [
            "microvm@${name}.service"
            "microvm-tap-interfaces@${name}.service"
            "microvm-pci-devices@${name}.service"
            "microvm-virtiofsd@${name}.service"
          ];
          requiredBy = [ "microvm@${name}.service" ];
          partOf = [ "microvm@${name}.service" ];
        }
      ))
    ));
  };
}
