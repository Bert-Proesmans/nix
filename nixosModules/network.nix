# This is a nixos module.  NixOSArgs -> AttrSet
{ config, lib, options, ... }:
let
  cfg = config.proesmans.networks;
  opt = options.proesmans.networks;
in
{
  options.proesmans.networks = {
    management = {
      dhcp.enable = lib.mkEnableOption (lib.mdDoc "Enable DHCP on the management interface");
      subnet = lib.mkOption {
        type = lib.net.types.cidr;
        default = null;
        description = lib.mdDoc ''
          The subnet address to be assigned to the management interface of the machine.
        '';
      };
      ip = lib.mkOption {
        type = lib.net.types.ip-in cfg.networks.management.subnet;
        default = null;
        description = lib.literalMD ''
          The IP, which must be inside the subnet provided by option config.${opt.networks.management.subnet}.
        '';
      };
    };

    service = {
      dhcp.enable = lib.mkEnableOption (lib.mdDoc "Enable DHCP on the service interface");
      subnet = lib.mkOption {
        type = lib.net.types.cidr;
        default = null;
        description = lib.mdDoc ''
          The subnet address to be assigned to the service interface of the machine.
        '';
      };
      ip = lib.mkOption {
        type = lib.net.types.ip-in cfg.networks.service.subnet;
        default = null;
        description = lib.literalMD ''
          The IP, which must be inside the subnet provided by option config.${opt.networks.service.subnet}.
        '';
      };
    };
  };

  config = { /* Not yet */ };
}
