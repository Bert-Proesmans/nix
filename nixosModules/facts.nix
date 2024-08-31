{ lib, config, options, ... }:
{
  options.proesmans.facts = lib.mkOption {
    type = lib.types.submodule {
      freeformType = lib.types.attrsOf lib.types.str;

      options = {
        # All options defined here will form a partial schema, their values will also be properly type-checked on query.

        tags = lib.mkOption {
          description = ''
            Collection of data to help filtering down records.
          '';
          type = lib.types.listOf (lib.types.enum [
            "bare-metal"
            "hypervisor"
            "virtual-machine"
          ]);
          apply = lib.lists.unique;
          default = [ ];
        };

        management.mac-address = lib.mkOption {
          description = ''
            The MAC address of the network interface that should be used for SSH host management.
            
            NOTE; The "locally administrated"-bit must be set for generated MAC addresses to make the change of random collision impossible!
            REF; https://www.hellion.org.uk/cgi-bin/randmac.pl
          '';
          type = lib.types.nullOr lib.net.types.mac;
          default = null;
        };

        management.ip-address = lib.mkOption {
          description = ''
            The IP address to use when attempting to SSH connect to this host.
          '';
          type = lib.types.nullOr lib.net.types.ip;
          default = null;
        };

        management.domain-name = lib.mkOption {
          description = ''
            The DNS name to use when attempting to SSH connect to this host.
          '';
          type = lib.types.nullOr lib.dns.types.domain-name;
          default = null;
        };

        meta.parent = lib.mkOption {
          description = ''
            Hostname of the parent controlling the start/stop state of (and access to) this host.
          '';
          type = lib.types.nullOr lib.types.str;
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
    management.domain-name = lib.mkIf (config.networking.hostName != null && config.networking.domain != null) "${config.networking.hostName}.${config.networking.domain}";

    meta.vsock-id = lib.mkIf (lib.hasAttrByPath [ "microvm" "vsock" "cid" ] config) config.microvm.vsock.cid;
  };
}
