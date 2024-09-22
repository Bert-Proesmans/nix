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
    microvm.qemu.extraArgs = lib.optionals (cfg.enable) [
      "-chardev"
      "socket,id=chardev-vsock,reconnect=0,path=${cfg.control-socket}"
      "-device"
      "vhost-user-vsock-pci,chardev=chardev-vsock"
    ];
  };
}
