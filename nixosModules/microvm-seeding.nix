{ lib, config, ... }:
let
  users = config.users.users;
in
{
  options.microvm-ext.seeds = lib.mkOption {
    description = "Shared sensitive material between host and guest";
    default = [ ];
    type = lib.types.listOf (lib.types.submodule ({ config, ... }: {
      options = {
        source = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Path to shared directory tree";
        };
        mountPoint = lib.mkOption {
          type = lib.types.path;
          description = "Where to mount the share inside the container";
        };
        mode = lib.mkOption {
          type = lib.types.str;
          default = "0400";
          description = ''
            Permissions mode of the in octal.
          '';
        };
        owner = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = ''
            User of the file.
          '';
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = users.${config.owner}.group;
          defaultText = lib.literalMD "{option}`config.users.users.\${owner}.group`";
          description = ''
            Group of the file.
          '';
        };
      };
    }));
  };


}
