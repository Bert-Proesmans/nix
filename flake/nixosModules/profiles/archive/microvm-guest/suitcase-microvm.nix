{ lib, config, ... }:
let
  #host-cfg = config;
  cfg = config.microvm.suitcase;
  hostName = config.networking.hostName or "$HOSTNAME";
  enable-suitcase = (builtins.length (lib.mapAttrsToList (_: _: true) cfg.secrets)) != 0;
in
{
  options.microvm.suitcase = {
    secrets = lib.mkOption {
      description = "Secrets collected and passed into the guest";
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }:
          {
            options = {
              name = lib.mkOption {
                description = "Name of the secrets file inside the guest";
                type = lib.types.str;
                default = config._module.args.name;
              };
              source = lib.mkOption {
                description = "Path to shared directory tree";
                type = lib.types.nonEmptyStr;
              };
              path = lib.mkOption {
                description = "Path where the secret becomes available";
                type = lib.types.str;
                default = "/run/in-secrets-microvm/${config.name}";
                readOnly = true;
              };

              # TODO ?
              # mode = lib.mkOption {
              #   description = "Permissions mode of the in octal";
              #   type = lib.types.str;
              #   default = "0400";
              # };
              # user = lib.mkOption {
              #   description = "User of the file";
              #   type = lib.types.str;
              #   default = host-cfg.users.users.root.name;
              # };
              # group = lib.mkOption {
              #   description = "Group of the file.";
              #   type = lib.types.str;
              #   default = host-cfg.users.${config.user}.group;
              #   defaultText = lib.literalMD "{option}`config.users.users.\${owner}.group`";
              # };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf enable-suitcase {
    assertions =
      builtins.map
        (secrets: {
          assertion = builtins.length secrets == 1;
          message = ''
            MicroVM ${hostName}: secret name "${(builtins.head secrets).name}" is used ${toString (builtins.length secrets)}" > 1 times.
          '';
        })
        (
          builtins.attrValues (
            builtins.groupBy ({ name, ... }: name) (lib.mapAttrsToList (_: v: v) cfg.secrets)
          )
        );

    microvm.volumes = [
      {
        # INFO; Use standard microvm.volumes options to load the suitcase into the guest

        autoCreate = false;
        # NOTE; NixOS automatically instructs the kernel to prepare the squashfs module for mounting
        fsType = "squashfs";
        image = "/var/lib/microvms/${hostName}/suitcase.squashfs";
        # WARN; Different name for incoming mounts, so stacking becomes possible
        mountPoint = "/run/in-secrets-microvm";
      }
    ];
  };
}
