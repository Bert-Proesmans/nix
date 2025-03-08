{ lib, config, ... }:
let
  cfg = config.microvm.vsock.forwarding;
in
{
  options.microvm.vsock.forwarding = {
    enable = lib.mkEnableOption "VSOCK transmissions between sibling guests";
    freeForAll = lib.mkEnableOption "Allow all guests to communicate with each other";
    cid = lib.mkOption {
      description = "The unique context identifier (CID) assigned to this guest";
      type = lib.types.nullOr lib.types.int;
      default = null;
    };

    allowTo = lib.mkOption {
      description = ''
        List of CIDs that can have bidirectional communications over VSOCK with the current guest.
      '';
      type = lib.types.listOf lib.types.int;
      default = [ ];
    };

    control-socket = lib.mkOption {
      description = "Basename of socket to communicate with the VSOCK host daemon";
      type = lib.types.str;
      default = "vsock-control.sock";
    };
  };

  config = {
    assertions = [
      ({
        assertion = cfg.enable -> config.microvm.vsock.cid == null;
        message = ''
          Options 'config.microvm.vsock.forwarding.enable' is incompatible with 'config.microvm.vsock.cid'.
          Unset the option 'config.microvm.vsock.cid' to enable VSOCK forwarding.
        '';
      })
      ({
        assertion = cfg.enable -> cfg.cid != null;
        message = ''
          VSOCK forwarding requires the cid option to be set.
          Add options 'microvm.vsock.forwarding.cid' to your configuration.
        '';
      })
    ];

    microvm.qemu.extraArgs = lib.optionals (cfg.enable) [
      # WARN; Assumes shared memory is already setup
      # This is done by setting up other virtio stuff like shares.
      "-chardev"
      "socket,id=chardev-vsock,reconnect=0,path=${cfg.control-socket}"
      "-device"
      "vhost-user-vsock-pci,chardev=chardev-vsock"
    ];
  };
}
