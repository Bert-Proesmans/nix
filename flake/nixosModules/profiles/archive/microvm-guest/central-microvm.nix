{ lib, config, ... }:
let
  cfg = config.microvm.central;
  hostName = config.networking.hostName or "$HOSTNAME";
  enable-central-share = builtins.length cfg.shares != 0;
in
{
  options.microvm.central = {
    tag = lib.mkOption {
      description = "Unique virtiofs daemon tag";
      type = lib.types.str;
      default = "central-${hostName}";
    };
    proto = lib.mkOption {
      description = "Protocol for this share";
      type = lib.types.enum [ "virtiofs" ];
      default = "virtiofs";
    };
    securityModel = lib.mkOption {
      description = "What security model to use for the shared directory";
      type = lib.types.enum [
        "passthrough"
        "none"
        "mapped"
        "mapped-file"
      ];
      default = "none";
    };
    socket = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if cfg.proto == "virtiofs" then "${hostName}-virtiofs-${cfg.tag}.sock" else null;
      description = "Socket for communication with virtiofs daemon";
    };
    shares = lib.mkOption {
      description = "Shared directory trees passed through a single guest mount";
      default = [ ];
      type = lib.types.listOf (
        lib.types.submodule (
          { ... }:
          {
            options = {
              tag = lib.mkOption {
                type = lib.types.str;
                description = "Unique virtiofs daemon tag";
              };
              source = lib.mkOption {
                type = lib.types.nonEmptyStr;
                description = "Path to shared directory tree";
              };
              mountPoint = lib.mkOption {
                type = lib.types.path;
                description = "Where to mount the shared directory tree inside the virtual machine";
              };
              read-only = lib.mkOption {
                description = "Bind mount the source as read-only";
                type = lib.types.bool;
                default = false;
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf enable-central-share {
    assertions = builtins.map (shares: {
      assertion = builtins.length shares == 1;
      message = ''
        MicroVM ${hostName}: share tag "${(builtins.head shares).tag}" is used ${toString (builtins.length shares)} > 1 times.
      '';
    }) (builtins.attrValues (builtins.groupBy ({ tag, ... }: tag) cfg.shares));

    microvm.shares = [
      {
        # INFO; Use standard microvm.share options to mount the base directory into the guest

        source = "/run/central-microvm/${hostName}";
        # WARN; Different name for incoming mounts, so stacking becomes possible
        mountPoint = "/run/in-central-microvm/${hostName}";
        tag = cfg.tag;
        proto = cfg.proto;
        securityModel = cfg.securityModel;
        socket = cfg.socket;
      }
    ];

    systemd.mounts = (
      lib.flip builtins.map config.microvm.central.shares (share: {
        # INFO; Mount each tag into the desired location

        what = "/run/in-central-microvm/${hostName}/${share.tag}";
        where = share.mountPoint;
        type = "none";
        options = lib.concatStringsSep "," [ "bind" ];

        unitConfig.RequiresMountsFor = [ "/run/in-central-microvm/${hostName}" ];
        # NOTE; By default, mounts are ordered before local-fs.target and requiring local-fs-pre.target.
        # Having the mounts exist before local-fs.target should be enough for all intuitive cases, except
        # for tools like sops that require data during stage-1/nixos-activation.
        #
        # NOTE; We _do_ need to _want_ the mount though, otherwise systemd will not mount the directory
        # until explicitly needed!
        wantedBy = [ "multi-user.target" ];
      })
    );
  };
}
