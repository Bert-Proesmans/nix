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
          type = lib.net.types.mac;
          default = null;
        };
      };
    };
  };

  # Setup some defaults that apply to all machines
  config.proesmans.facts = {
    inherit (config.networking) hostName domain;
  };
}
