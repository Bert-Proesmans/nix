{ lib, pkgs, config, ... }:
let
  cfg = config.proesmans.mount-central;
  path-mount-central = "/shared";
in
{
  options = {
    proesmans.mount-central = {
      defaults.after-units = lib.mkOption {
        description = ''
          Names of units that should be ordered before all mounts.
        '';
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "zfs-mount.service" ];
      };

      directories = lib.mkOption {
        description = ''
          Create a central directory '${path-mount-central}' where bind mounts are put into.
        '';
        default = { };
        type = lib.types.attrsOf (lib.types.submodule ({ name, config, ... }: {
          options = {
            enable = lib.mkEnableOption "mount subgroup" // { default = true; };

            path = lib.mkOption {
              description = ''
                Path relative to '${path-mount-central}' that is the container (directory) of the defined mounts.
              '';
              type = lib.types.str;
            };

            bind-paths = lib.mkOption {
              description = ''
                List of the mounted paths that are defined within this directory block.
              '';
              type = lib.types.listOf lib.types.path;
              default = lib.mapAttrsToList (_: v: "${path-mount-central}/${config.path}/${v.path}") config.mounts;
              readOnly = true;
            };

            mounts = lib.mkOption {
              description = ''
                Information about a specific mount to put into the above container.
              '';
              default = { };
              type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
                options = {
                  enable = lib.mkEnableOption "mount" // { default = true; };

                  source = lib.mkOption {
                    description = "The directory path that will be bind mounted";
                    type = lib.types.path;
                  };

                  path = lib.mkOption {
                    description = ''
                      Path relative to the parent mount group container that is bind-mounted to {option}`source`.
                    '';
                    type = lib.types.str;
                  };

                  read-only = lib.mkOption {
                    description = ''
                      Bind mount the source as read-only.
                    '';
                    type = lib.types.bool;
                    default = false;
                  };

                  after-units = lib.mkOption {
                    description = ''
                      Names of units that should be ordered before this mount.
                    '';
                    type = lib.types.listOf lib.types.str;
                    default = cfg.defaults.after-units;
                    example = [ "zfs-mount.service" ];
                  };
                };
                config = {
                  # Mount config
                  path = lib.mkDefault name;
                };
              }));
            };
          };

          config = {
            # Mount container config
            enable = lib.mkDefault (builtins.any (v: v == true) (lib.mapAttrsToList (_: v: v.enable) config.mounts));
            path = lib.mkDefault name;
          };
        }));
      };
    };
  };

  config =
    let
      flatten-mounts = mount: lib.pipe mount [
        (lib.mapAttrsToList (_: v: v))
        (builtins.filter (v: v.enable))
      ];
      enabled-mounts = lib.pipe cfg.directories [
        (lib.filterAttrs (_: v: v.enable))
        (builtins.mapAttrs (_: v: flatten-mounts v.mounts))
        (lib.filterAttrs (_: v: (builtins.length v) != 0))
      ];
      enable = (builtins.length (lib.mapAttrsToList (_: _: true) enabled-mounts)) != 0;
    in
    lib.mkIf enable {
      # Global config
      systemd.mounts = [
        ({
          # RAMfs does not support posix ACL nor size limits!
          what = "tmpfs";
          where = path-mount-central;
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
            # This folder is the shield between host and guests, so limited permissions
            # to prevent contaminating the other.
            "mode=0700"
            "uid=0"
            "gid=0"
            # More mounting options for security/robustness
            "noswap"
            "nosuid"
            "nodev"
            "noatime"
          ];

          # WARN; By default, mounts are ordered before local-fs.target and requiring local-fs-pre.target.
          # This mount must execute before local-fs-pre to keep other mounts working as expected!
          unitConfig.DefaultDependencies = "no";
          before = [ "umount.target" "local-fs-pre.target" ];
          wantedBy = [ "local-fs-pre.target" ]; # Prep the path before sysinit services kick in
          conflicts = [ "umount.target" ]; # For shutdown behaviour
        })
      ]
      # Append bind mount units for each enabled mount
      ++ (lib.pipe enabled-mounts [
        (lib.mapAttrsToList (host-name: list-mounts: (
          builtins.map
            (v: {
              what = v.source;
              where = "${path-mount-central}/${host-name}/${v.path}";
              type = "none";
              options = lib.concatStringsSep "," (
                [ "bind" ]
                  ++ lib.optionals v.read-only [ "ro" ]
              );
              after = v.after-units;

              # NOTE; Loosen up ordering constraints of mount
              # This is useful to mount in non-local sources like NFS, or ZFS datasets which do not order before
              # local-fs.target by default!
              unitConfig.DefaultDependencies = "no";
              unitConfig.RequiresMountsFor = [ path-mount-central ];
              before = [ "umount.target" ];
              conflicts = [ "umount.target" ];
              wantedBy = [ "multi-user.target" ];
            })
            list-mounts
        )))
        (lib.flatten)
      ])
      ;

      systemd.services."mount-central" = {
        description = "Mount central directory structure for guest sharing";
        # WARN; By default, mounts are ordered before local-fs.target and requiring local-fs-pre.target.
        # WARN; Service is executed before local-fs-pre so normal mounts can bind on top of these directories.
        before = [ "shutdown.target" "local-fs-pre.target" ];
        wantedBy = [ "local-fs-pre.target" ];
        conflicts = [ "shutdown.target" ];

        # NOTE; This service is automatically 
        unitConfig.DefaultDependencies = "no";
        unitConfig.RequiresMountsFor = [ path-mount-central ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          UMask = "0022";
          ExecStart =
            let
              bash-path-mounts = lib.pipe enabled-mounts [
                (lib.mapAttrsToList (host-name: list-mounts: builtins.map (v: "${host-name}/${v.path}") list-mounts))
                (lib.flatten)
                (builtins.map (v: lib.escapeShellArg v))
              ];
              script = pkgs.writeShellApplication {
                name = "base-dirs-shared-mount";
                runtimeInputs = [ pkgs.coreutils pkgs.findutils ];
                # WARN; ''\ escapes the following character. Used to escape the dollar sign
                text = ''
                  # Exit early if directory is not empty
                  # WARN; This service is running a second time if the directory is not empty!
                  [ -z "$(find /shared -mindepth 1 -print -quit)" ] || exit 0

                  machine_names=(${lib.concatStringsSep " " bash-path-mounts})
                  for name in "''\${machine_names[@]}"; do
                    mkdir --parents /shared/"$name"
                  done
                '';
              };
            in
            lib.getExe script;
          ExecStartPost =
            let
              script = pkgs.writeShellApplication {
                name = "ro-remount-shared";
                runtimeInputs = [ pkgs.mount ];
                text = ''
                  mount -o remount,ro ${path-mount-central}
                '';
              };
            in
            lib.getExe script;
          ExecStop =
            let
              script = pkgs.writeShellApplication {
                name = "rw-remount-shared";
                runtimeInputs = [ pkgs.mount ];
                text = ''
                  # or systemctl restart shared.mount
                  mount -o remount,rw ${path-mount-central}
                '';
              };
            in
            lib.getExe script;
        };
      };
    };
}
