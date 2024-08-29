{ lib, config, options, ... }:
let
  cfg = config.proesmans.facts;
in
{
  options.proesmans.facts = lib.mkOption {
    type = lib.types.submodule {
      freeformType = lib.types.attrsOf lib.types.str;

      options = {
        # All options defined here will form a partial schema, their values will also be properly type-checked on query.

        management.mac-address = lib.mkOption {
          description = ''
            The MAC address of the network interface that should be used for SSH host management.
            
            NOTE; The "locally administrated"-bit must be set for generated MAC addresses to make the change of random collision impossible!
            REF; https://www.hellion.org.uk/cgi-bin/randmac.pl
          '';
          type = lib.types.nullOr lib.net.types.mac;
          default = null;
        };

        meta.vsock-id = lib.mkOption {
          description = ''
            The virtual socket identifier (VSOCK ID) that uniquely identifies this virtual machine host.
            This ID is only valid on the physical host this virtual machine is running on. Both hypervisor and
            other virtual machines can setup a communication channel using this VSOCK ID.
          '';
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
        };
      };
    };
  };

  # Setup some defaults that apply to all machines
  config.proesmans.facts = {
    host-name = lib.mkIf (config.networking.hostName != null) config.networking.hostName;
    domain = lib.mkIf (config.networking.domain != null) config.networking.domain;

    meta.vsock-id = lib.mkIf (lib.hasAttrByPath [ "microvm" "vsock" "cid" ] config) config.microvm.vsock.cid;
  };
}
